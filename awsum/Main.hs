-- | Awsum compiler CLI
--   This entrypoint wires together parsing, typechecking, formatting,
--   code generation (LLVM/JVM/CLR/WASM/JS), and a tiny runner for those targets.
module Main (main) where

import Awsum.Codegen
import Awsum.Codegen.CLR (codegenCLR)
import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.JVM.Assemble (assembleJVM, renderJvmLimitExceeded)
import Awsum.Codegen.LLVM (codegenLLVM, llvmHostFromSystem, llvmHostLinkerFlags, llvmLinkHostFromSystem)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core (CoreProgram, PreludeTags)
import Awsum.Diagnostic
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.Lsp (runLspServer)
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Prelude (stripPreludeWarnings, verifyPrelude, withPrelude)
import Awsum.Program (ProgramType, parseProgramType)
import Awsum.RestrictPreludeRefs (restrictPreludeRefs)
import Awsum.Symbols (symbolsOfProgram, symbolsToJson)
import Awsum.Syntax
import Awsum.Typing (TypeError, Warning, prettyPrintTypeError, requireMain)
import Awsum.Version qualified as Meta
import Common.File
import Control.Concurrent.Async (concurrently)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (showVersion)
import Options.Applicative qualified as OA
import Relude
import System.Exit (ExitCode (..))
import System.FilePath (dropExtension, (</>))
import System.IO (hIsTerminalDevice, hSetBinaryMode)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, readProcessWithExitCode, waitForProcess)
import Text.Pretty.Simple (pPrint)

-- | Rendered version string, e.g. "9.9.9".
awsumVersion :: Text
awsumVersion = toText (showVersion Meta.version)

-- | Top-level CLI command.
--
-- Commands that go through the typechecker take a 'ProgramType' (set
-- by the mandatory @--program-type@ flag); @ast@, @format@ and
-- @symbols@ are purely syntactic and skip it.
data Command
  = CmdVersion
  | -- | file, programType, useJson, strict
    CmdCheck FilePath ProgramType Bool Bool
  | -- | file, programType, target, out
    CmdBuild FilePath ProgramType Target (Maybe FilePath)
  | -- | file, programType, target, forwardedArgs
    CmdRun FilePath ProgramType Target [Text]
  | CmdAST FilePath
  | -- | file, programType
    CmdCore FilePath ProgramType
  | -- | file, programType, target (JVM/WASM only)
    CmdAsm FilePath ProgramType Target
  | -- | file, inPlace
    CmdFormat FilePath Bool
  | -- | file, useJson
    CmdSymbols FilePath Bool
  | -- | Run the LSP server. The transport must be specified explicitly
    --   (the only one supported today is stdio, but the choice is part
    --   of the contract — same "no defaulting" rule that applies to
    --   integer literal types and program-type selection elsewhere in
    --   the CLI).
    CmdLsp LspTransport
  deriving stock (Show)

-- | LSP transport selector. New transports (TCP socket, named pipe, …)
--   land here as additional constructors, each gated by its own
--   mutually-exclusive flag in the parser.
data LspTransport = LspStdio
  deriving stock (Show)

-- ════════════════════════════════════════════════════════════════════════════
-- CLI parsers
-- ════════════════════════════════════════════════════════════════════════════

-- | Required positional: path to a source file.
argFilePath :: OA.Parser FilePath
argFilePath = OA.strArgument (OA.metavar "FILE")

-- | Mandatory program-type selector. Decides which platform-effect
--   table the typechecker and lowering see (see 'Awsum.Program'). We
--   deliberately require the flag rather than defaulting to @cli@ to
--   force an explicit choice.
optProgramType :: OA.Parser ProgramType
optProgramType =
  OA.option
    (OA.eitherReader (first toString . parseProgramType . toText))
    ( OA.long "program-type"
        <> OA.metavar "PROGRAM_TYPE"
        <> OA.help "Program type: cli"
        <> OA.completeWith ["cli"]
    )

-- | Required target backend selector.
optTarget :: OA.Parser Target
optTarget =
  OA.option
    (OA.maybeReader readTarget)
    ( OA.long "target"
        <> OA.short 't'
        <> OA.metavar "TARGET"
        <> OA.help "Target backend: llvm | jvm | clr | wasm | js"
        <> OA.completeWith ["llvm", "jvm", "clr", "wasm", "js"]
    )
  where
    readTarget :: String -> Maybe Target
    readTarget = \case
      "llvm" -> Just TargetLLVM
      "jvm" -> Just TargetJVM
      "clr" -> Just TargetCLR
      "wasm" -> Just TargetWASM
      "js" -> Just TargetJS
      _ -> Nothing

-- | Optional: output file path (defaults to stdout).
optOutputPath :: OA.Parser (Maybe FilePath)
optOutputPath =
  optional
    $ OA.strOption
      ( OA.long "out"
          <> OA.short 'o'
          <> OA.metavar "OUT"
          <> OA.help "Output file (default: stdout)"
      )

-- | Command-line arguments forwarded to the program, read back through
--   'IO.Args.getArgs' as a @List String@. Everything after the @FILE@ —
--   conventionally after a @--@ separator — is collected here, so
--   @awsum run … FILE -- a b c@ delivers @["a", "b", "c"]@ and a bare
--   @awsum run … FILE@ delivers @Nil@. Stdin is a separate, independent
--   channel: 'awsum run' inherits its own stdin to the child process, so
--   @echo \"data\" | awsum run …@ reaches the child's @IO.Stdin.readAllString@
--   / @IO.Stdin.readAllBytes@ verbatim. The two channels can be used together.
argForwardedArgs :: OA.Parser [Text]
argForwardedArgs =
  many
    ( (toText :: String -> Text)
        <$> OA.strArgument
          ( OA.metavar "-- ARGS..."
              <> OA.help "Arguments forwarded to the program (read via IO.Args.getArgs)"
          )
    )

-- | Flag: rewrite the file in place when formatting.
optInPlace :: OA.Parser Bool
optInPlace =
  OA.switch
    ( OA.long "in-place"
        <> OA.short 'i'
        <> OA.help "Rewrite FILE with formatted source"
    )

-- | Flag: output diagnostics as JSON.
optJson :: OA.Parser Bool
optJson = OA.switch (OA.long "json" <> OA.help "Output diagnostics as JSON")

-- | Mandatory LSP transport selector. Today only @--stdio@ is
--   accepted; the option is required (via 'flag'') so that adding a
--   second transport later (e.g. @--socket PORT@) is a non-breaking
--   change and so that no command line ever runs the server with an
--   implicit transport.
optLspTransport :: OA.Parser LspTransport
optLspTransport =
  OA.flag'
    LspStdio
    ( OA.long "stdio"
        <> OA.help "Use stdio (the only supported transport today)"
    )

-- | Flag: treat warnings as errors (fail with non-zero exit).
optStrict :: OA.Parser Bool
optStrict =
  OA.switch
    ( OA.long "strict"
        <> OA.help "Treat warnings as errors (non-zero exit if any warning)"
    )

-- | Subcommand builder.
subcmd :: String -> String -> OA.Parser a -> OA.Mod OA.CommandFields a
subcmd name desc p = OA.command name (OA.info p (OA.progDesc desc))

-- | Global '--version' option parser (returns CmdVersion when present).
pVersionFlag :: OA.Parser Command
pVersionFlag =
  OA.flag'
    CmdVersion
    ( OA.long "version"
        <> OA.help "Print version and exit"
    )

-- | Command parser.
pCommand :: OA.Parser Command
pCommand =
  -- Allow the global --version flag alongside subcommands.
  pVersionFlag
    <|> OA.hsubparser
      ( subcmd "check" "Parse and typecheck a file" (CmdCheck <$> argFilePath <*> optProgramType <*> optJson <*> optStrict)
          <> subcmd "build" "Compile file to target language" (CmdBuild <$> argFilePath <*> optProgramType <*> optTarget <*> optOutputPath)
          <> subcmd "run" "Compile and run (forward args after --)" (CmdRun <$> argFilePath <*> optProgramType <*> optTarget <*> argForwardedArgs)
          <> subcmd "ast" "Print parsed AST" (CmdAST <$> argFilePath)
          <> subcmd "core" "Print elaborated Core" (CmdCore <$> argFilePath <*> optProgramType)
          <> subcmd "asm" "Print target assembly text (jvm, wasm)" (CmdAsm <$> argFilePath <*> optProgramType <*> optTarget)
          <> subcmd "format" "Format source (render . parse)" (CmdFormat <$> argFilePath <*> optInPlace)
          <> subcmd "symbols" "Print top-level symbols (outline)" (CmdSymbols <$> argFilePath <*> optJson)
          <> subcmd "lsp" "Run Language Server Protocol (transport: --stdio)" (CmdLsp <$> optLspTransport)
      )

-- | Top-level Options.Applicative info.
cliInfo :: OA.ParserInfo Command
cliInfo =
  OA.info
    (OA.helper <*> pCommand)
    ( OA.fullDesc
        <> OA.progDesc "Awsum compiler CLI"
        <> OA.header "Awsum — strict FP with capabilities"
    )

-- ════════════════════════════════════════════════════════════════════════════
-- Main/dispatch
-- ════════════════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  cmd <- OA.execParser cliInfo
  runCommand cmd

-- | Execute a parsed command.
runCommand :: Command -> IO ()
runCommand = \case
  CmdVersion -> putTextLn awsumVersion
  CmdCheck filePath progType useJson strict -> runCheck filePath progType useJson strict
  CmdBuild filePath progType target mOut -> do
    (ptags, core) <- compileToCoreOrDie progType filePath
    -- (warnings are emitted to stderr by compileToCoreOrDie)
    case target of
      TargetJVM ->
        case assembleJVM ptags core of
          Left err -> die (toString (renderJvmLimitExceeded err))
          Right bytes ->
            case mOut of
              Nothing -> BS.hPut stdout bytes
              Just out -> writeFileBS out bytes
      TargetCLR -> do
        let bytes = assembleCLR ptags core
        case mOut of
          Nothing -> BS.hPut stdout bytes
          Just out -> do
            writeFileBS out bytes
            let rcPath = dropExtension out <> ".runtimeconfig.json"
            writeFileText rcPath runtimeConfigJson
      TargetWASM -> do
        let bytes = assembleWASM ptags core
        case mOut of
          Nothing -> BS.hPut stdout bytes
          Just out -> writeFileBS out bytes
      _ -> do
        let code = codegenText progType target ptags core
        case mOut of
          Nothing -> putTextLn code
          Just out -> writeFileText out code
  CmdRun filePath progType target forwardedArgs -> do
    (ptags, core) <- compileToCoreOrDie progType filePath
    runOnTarget progType target ptags core forwardedArgs
  CmdAST filePath -> do
    prog <- parseFileOrDie filePath
    pPrint prog
  CmdCore filePath progType -> do
    verifyPreludeOrDie progType
    userProg <- parseFileOrDie filePath
    checkPreludeRefsOrDie filePath userProg
    let prog = withPrelude userProg
    case elaborateLowerProgram progType prog of
      Left err -> die $ toString (prettyPrintTypeError err)
      Right (warns, _ptags, ir) -> do
        emitWarningsToStderr filePath (stripPreludeWarnings warns)
        pPrint ir
  CmdAsm filePath progType target -> do
    (ptags, core) <- compileToCoreOrDie progType filePath
    case target of
      TargetJVM -> putTextLn (codegenJVM ptags core)
      TargetCLR -> putTextLn (codegenCLR ptags core)
      TargetWASM -> putTextLn (codegenWASM ptags core)
      _ -> die "asm is only supported for jvm, clr, and wasm targets"
  CmdFormat filePath inPlace -> do
    src <- readFileTextUtf8 filePath
    case formatSource src of
      Left e -> die $ toString e
      Right formatted ->
        if inPlace
          then writeFileText filePath formatted
          else putTextLn formatted
  CmdSymbols filePath useJson -> do
    prog <- parseFileOrDie filePath
    let syms = symbolsOfProgram prog
    if useJson
      then putTextLn (symbolsToJson syms)
      else pPrint syms
  CmdLsp LspStdio -> void (runLspServer awsumVersion)

-- ════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Select the text codegen for a target. Some targets (@JS@) are
--   parameterized by 'ProgramType' because their wrapping strategy
--   depends on it.
codegenText :: ProgramType -> Target -> PreludeTags -> CoreProgram -> Text
codegenText progType = \case
  TargetLLVM -> codegenLLVM llvmHostFromSystem
  TargetJVM -> codegenJVM
  TargetCLR -> codegenCLR
  TargetWASM -> codegenWASM
  TargetJS -> codegenJS progType

-- | Compile Core to target and run using the appropriate system runtime.
runOnTarget :: ProgramType -> Target -> PreludeTags -> CoreProgram -> [Text] -> IO ()
runOnTarget progType target ptags core args = case target of
  TargetLLVM ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let llPath = dir </> "out.ll"
          binPath = dir </> "out"
      writeFileText llPath (codegenLLVM llvmHostFromSystem ptags core)
      -- AWSUM_CLANG: optional absolute path to clang. Useful on hosts where
      -- the PATH-resolved 'clang' points at an outdated LLVM (e.g. GHC's
      -- bundled mingw clang on Windows when invoked through Stack).
      clangPath <- fromMaybe "clang" . mfilter (not . null) <$> lookupEnv "AWSUM_CLANG"
      -- IR shape (POSIX vs Windows footer) and link-host flags
      -- are separate axes: macOS and Linux share the POSIX
      -- footer; Windows needs explicit shell32/kernel32 links
      -- ('llvmHostLinkerFlags' for the per-host detail).
      -- 'llvmLinkHostFromSystem' detects the linker
      -- independently of 'llvmHostFromSystem'.
      (exitClang, stdoutClang, stderrClang) <- readProcessWithExitCode clangPath (["-O2", "-Wno-override-module", llPath, "-o", binPath] <> llvmHostLinkerFlags llvmLinkHostFromSystem) ""
      case exitClang of
        ExitFailure n ->
          die
            $ toString
            $ "clang error (exit "
            <> show n
            <> ")\nstderr:\n"
            <> toText stderrClang
            <> "\nstdout:\n"
            <> toText stdoutClang
        ExitSuccess -> runChild "runtime error" binPath (map toString args)
  TargetJVM ->
    case assembleJVM ptags core of
      Left err -> die (toString (renderJvmLimitExceeded err))
      Right bytes ->
        withSystemTempDirectory "awsum" $ \dir -> do
          let classPath = dir </> "AwsumMain.class"
          writeFileBS classPath bytes
          -- Pin the JVM's I/O charsets to UTF-8 so 'argv' survives the
          -- startup decode on hosts whose default charset isn't UTF-8 (the
          -- usual Windows case, where 'sun.jnu.encoding' otherwise comes
          -- from the system ANSI code page and supplementary code points
          -- collapse to '?' before our 'main' runs). Stdout side is handled
          -- inside the emitted 'main' itself via a 'System.setOut' prologue.
          runChild "java error" "java" (["-Dsun.jnu.encoding=UTF-8", "-Dfile.encoding=UTF-8", "-cp", dir, "AwsumMain"] <> map toString args)
  TargetCLR ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let dllPath = dir </> "AwsumMain.dll"
          rcPath = dir </> "AwsumMain.runtimeconfig.json"
      writeFileBS dllPath (assembleCLR ptags core)
      writeFileText rcPath runtimeConfigJson
      runChild "dotnet error" "dotnet" ([dllPath] <> map toString args)
  TargetWASM ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let wasmPath = dir </> "out.wasm"
      writeFileBS wasmPath (assembleWASM ptags core)
      runChild "wasmtime error" "wasmtime" ([wasmPath] <> map toString args)
  TargetJS ->
    runText "node" ".js" (codegenJS progType ptags core) args

-- | Write text code to a temp file and run with the given interpreter.
runText :: String -> String -> Text -> [Text] -> IO ()
runText cmd ext code args =
  withSystemTempDirectory "awsum" $ \dir -> do
    let outPath = dir </> "out" <> ext
    writeFileText outPath code
    runChild (toText cmd <> " error") cmd ([outPath] <> map toString args)

-- | Run a compiled program. The child inherits the calling process's
--   stdin so 'IO.Stdin.readAllString' / 'IO.Stdin.readAllBytes' receive whatever the user piped into
--   'awsum run' (single source of truth — no flag, no buffering). The
--   child's stdout is captured and printed verbatim, preserving the
--   contract that 'awsum run' writes the program's stdout to its own
--   stdout. The child's stderr is captured so a non-zero exit can be
--   reported with the runtime's diagnostic text. stdout and stderr are
--   drained concurrently to avoid pipe-buffer deadlocks on programs
--   that emit more than one buffer's worth before exiting.
runChild :: Text -> FilePath -> [String] -> IO ()
runChild errLabel cmd args = do
  (_, Just hout, Just herr, ph) <-
    createProcess
      (proc cmd args)
        { std_in = Inherit,
          std_out = CreatePipe,
          std_err = CreatePipe
        }
  hSetBinaryMode hout True
  hSetBinaryMode herr True
  (outBs, errBs) <- concurrently (BS.hGetContents hout) (BS.hGetContents herr)
  exit <- waitForProcess ph
  case exit of
    ExitSuccess -> putTextLn (decodeUtf8 outBs)
    ExitFailure _ -> die $ toString (errLabel <> ":\n" <> decodeUtf8 errBs)

-- | .NET runtime configuration template for CLR target.
runtimeConfigJson :: Text
runtimeConfigJson =
  "{\n\
  \  \"runtimeOptions\": {\n\
  \    \"tfm\": \"net9.0\",\n\
  \    \"framework\": {\n\
  \      \"name\": \"Microsoft.NETCore.App\",\n\
  \      \"version\": \"9.0.0\"\n\
  \    },\n\
  \    \"rollForward\": \"LatestMajor\"\n\
  \  }\n\
  \}\n"

-- | Parse → typecheck → lower to Core, or terminate with an error.
--   Warnings are printed to stderr but do not block compilation. Use
--   @awsum check --strict@ for a CI-friendly fail-on-warning flow.
--
--   Unlike plain 'typecheckProgram', this path is for commands that produce
--   an executable (@build@, @run@, @asm@) and therefore enforces the
--   entry-point contract via 'requireMain'.
compileToCoreOrDie :: ProgramType -> FilePath -> IO (PreludeTags, CoreProgram)
compileToCoreOrDie progType filePath = do
  verifyPreludeOrDie progType
  userProg <- parseFileOrDie filePath
  checkPreludeRefsOrDie filePath userProg
  let prog = withPrelude userProg
  case requireMain prog of
    Left err -> dieWithTypeError filePath err
    Right () -> pass
  case elaborateLowerProgram progType prog of
    Left err -> dieWithTypeError filePath err
    Right (warns, ptags, core) -> do
      emitWarningsToStderr filePath (stripPreludeWarnings warns)
      pure (ptags, core)

-- | Typecheck the bundled prelude before processing any user file. A
--   failure here is a compiler bug — the prelude ships with the binary —
--   so we die with an @Internal compiler error@ prefix rather than a
--   normal user-facing diagnostic.
verifyPreludeOrDie :: ProgramType -> IO ()
verifyPreludeOrDie progType = case verifyPrelude progType of
  Right _warns -> pass
  Left err ->
    die
      . toString
      $ "Internal compiler error: stdlib/Prelude.aww failed to typecheck:\n"
      <> prettyPrintTypeError err

-- | Reject user-source references to prelude-private names (the
--   constructors of @type IO@ and @runIO@). Runs after parse, before
--   'withPrelude' splices the prelude in, so the diagnostic precedes
--   any \"Unbound name\" cascade the typechecker would otherwise emit
--   for the same identifier. Idempotent on the prelude itself; see
--   "Awsum.RestrictPreludeRefs".
checkPreludeRefsOrDie :: FilePath -> Program -> IO ()
checkPreludeRefsOrDie filePath userProg = case restrictPreludeRefs userProg of
  [] -> pass
  vs -> dieWithDiagnostics filePath (map preludeRefViolationToDiagnostic vs)

-- | Render warnings on stderr in human-readable form so build/run/asm
--   commands surface them without breaking their stdout contract.
emitWarningsToStderr :: FilePath -> [Warning] -> IO ()
emitWarningsToStderr _ [] = pass
emitWarningsToStderr filePath warns = do
  source <- readFileTextUtf8 filePath
  useColor <- colorEnabled
  let diags = map warningToDiagnostic warns
  TIO.hPutStrLn stderr (formatDiagnostics useColor filePath source diags)

-- | Read a file as UTF-8 and parse a 'Program' or terminate with an error.
parseFileOrDie :: FilePath -> IO Program
parseFileOrDie filePath = do
  text <- readFileTextUtf8 filePath
  case parseProgramDiagnostic text of
    Left parseErrs -> dieWithDiagnostics filePath (map parseErrorToDiagnostic parseErrs)
    Right p -> pure p

-- ════════════════════════════════════════════════════════════════════════════
-- check command
-- ════════════════════════════════════════════════════════════════════════════

-- | The full @awsum check@ flow: parse, typecheck, render diagnostics in
--   the requested format, and choose an exit code.
--
-- Exit-code rules:
--   • Errors (parse failure, type error)    → exit 1.
--   • Warnings without @--strict@          → exit 0.
--   • Warnings with @--strict@             → exit 1.
--   • Clean program                        → exit 0 (and a friendly @"OK"@
--                                              line in the non-JSON path).
runCheck :: FilePath -> ProgramType -> Bool -> Bool -> IO ()
runCheck filePath progType useJson strict = do
  verifyPreludeOrDie progType
  src <- readFileTextUtf8 filePath
  -- Go through the full 'elaborateLowerProgram' pipeline (not plain
  -- 'typecheckProgram') so 'check' also surfaces post-lowering
  -- diagnostics like stack-safety violations caught by the
  -- 'Awsum.StackSafety' verifier. Typing-level errors still bubble up
  -- through the same 'Either' channel.
  let result = case parseProgramDiagnostic src of
        Left parseErrs -> Left (map parseErrorToDiagnostic parseErrs)
        Right userProg -> case restrictPreludeRefs userProg of
          vs@(_ : _) -> Left (map preludeRefViolationToDiagnostic vs)
          [] ->
            case elaborateLowerProgram progType (withPrelude userProg) of
              Left typeErr -> Left [typeErrorToDiagnostic typeErr]
              Right (warns, _ptags, _core) ->
                Right (map warningToDiagnostic (stripPreludeWarnings warns))
  let diagnostics = either id id result
      hasError = isLeft result
      hasWarn = not (null diagnostics) && not hasError
      shouldFail = hasError || (strict && hasWarn)
  if useJson
    then do
      putTextLn (diagnosticsToJson diagnostics)
      when shouldFail exitFailure
    else do
      useColor <- colorEnabled
      case diagnostics of
        [] -> putTextLn "OK"
        _ -> do
          let rendered = formatDiagnostics useColor filePath src diagnostics
          if hasError
            then die (toString rendered)
            else do
              TIO.hPutStrLn stderr rendered
              when shouldFail exitFailure

-- ════════════════════════════════════════════════════════════════════════════
-- Terminal rendering
-- ════════════════════════════════════════════════════════════════════════════

-- | Report a 'TypeError' with the offending source line shown.
dieWithTypeError :: FilePath -> TypeError -> IO a
dieWithTypeError filePath err =
  dieWithDiagnostics filePath [typeErrorToDiagnostic err]

-- | Render and print diagnostics, then exit with a non-zero status.
--   Re-reads the source file so the offending line can be shown verbatim.
dieWithDiagnostics :: FilePath -> [Diagnostic] -> IO a
dieWithDiagnostics filePath diags = do
  source <- readFileTextUtf8 filePath
  useColor <- colorEnabled
  die $ toString $ formatDiagnostics useColor filePath source diags

-- | Should terminal colour be emitted?  Respects @NO_COLOR@ and only
--   colours output when stderr is an interactive terminal.
colorEnabled :: IO Bool
colorEnabled = do
  noColor <- lookupEnv "NO_COLOR"
  case noColor of
    Just _ -> pure False
    Nothing -> hIsTerminalDevice stderr

-- | Format diagnostics. Errors use bold red; warnings use
--   bold yellow. Each diagnostic header line (e.g. @-- Error: file:line:col@)
--   is recognized by VS Code's terminal link provider as clickable.
--
-- Example error:
--
-- @
-- -- Error: path/to/file.aww:8:11
-- 8 |overMax = 256
--   |          ^^^
--   |          Integer literal 256 out of range for UInt8 (valid range: 0..255)
-- @
formatDiagnostics :: Bool -> FilePath -> Text -> [Diagnostic] -> Text
formatDiagnostics useColor filePath source = T.intercalate "\n\n" . map formatOne
  where
    sourceLines = lines source

    boldColor :: Severity -> Text -> Text
    boldColor sev t
      | not useColor = t
      | otherwise = case sev of
          SevError -> "\ESC[1;31m" <> t <> "\ESC[0m"
          SevWarning -> "\ESC[1;33m" <> t <> "\ESC[0m"

    color :: Severity -> Text -> Text
    color sev t
      | not useColor = t
      | otherwise = case sev of
          SevError -> "\ESC[31m" <> t <> "\ESC[0m"
          SevWarning -> "\ESC[33m" <> t <> "\ESC[0m"

    severityLabel :: Severity -> Text
    severityLabel = \case
      SevError -> "Error"
      SevWarning -> "Warning"

    formatOne :: Diagnostic -> Text
    formatOne (Diagnostic sev (SrcSpan sl sc el ec) msg _fixes) =
      let lineText = case drop (sl - 1) sourceLines of
            (l : _) -> l
            [] -> ""
          lineNumStr = show (sl :: Int)
          gutter = lineNumStr <> " |"
          emptyGutter = T.replicate (T.length lineNumStr) " " <> " |"
          caretIndent = T.replicate (max 0 (sc - 1)) " "
          caretLen
            | sl == el && ec > sc = ec - sc
            | sl == el = 1
            | otherwise = max 1 (T.length lineText - sc + 1)
          carets = T.replicate caretLen "^"
          header = boldColor sev ("-- " <> severityLabel sev <> ": " <> toText filePath <> ":" <> show sl <> ":" <> show sc)
          msgIndent = emptyGutter <> caretIndent
          -- Some diagnostics (notably Megaparsec parse errors) include newlines;
          -- indent every continuation line so the gutter stays aligned.
          indentedMsg = T.intercalate ("\n" <> msgIndent) (lines msg)
       in T.intercalate
            "\n"
            [ header,
              gutter <> lineText,
              emptyGutter <> caretIndent <> color sev carets,
              msgIndent <> indentedMsg
            ]
