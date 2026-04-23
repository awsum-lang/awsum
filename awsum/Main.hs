-- | Awsum compiler CLI
--   This entrypoint wires together parsing, typechecking, formatting,
--   code generation (LLVM/JVM/CLR/WASM/JS/Lua), and a tiny runner for those targets.
module Main (main) where

import Awsum.Codegen
import Awsum.Codegen.CLR (codegenCLR)
import Awsum.Codegen.CLR.Assemble (assembleCLR)
import Awsum.Codegen.JS (codegenJS)
import Awsum.Codegen.JVM (codegenJVM)
import Awsum.Codegen.JVM.Assemble (assembleJVM)
import Awsum.Codegen.LLVM (codegenLLVM)
import Awsum.Codegen.Lua (codegenLua)
import Awsum.Codegen.WASM (codegenWASM)
import Awsum.Codegen.WASM.Assemble (assembleWASM)
import Awsum.Core (CoreProgram)
import Awsum.Diagnostic
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Prelude (stripPreludeWarnings, verifyPrelude, withPrelude)
import Awsum.Program (ProgramType, parseProgramType)
import Awsum.Symbols (symbolsOfProgram, symbolsToJson)
import Awsum.Syntax
import Awsum.Typing (TypeError, Warning, prettyPrintTypeError, requireMain, typecheckProgram)
import Common.File
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (showVersion)
import Options.Applicative qualified as OA
import Paths_awsum qualified as Meta
import Relude
import System.Exit (ExitCode (..))
import System.FilePath (dropExtension, (</>))
import System.IO (hIsTerminalDevice)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Text.Pretty.Simple (pPrint)

-- | Rendered version string, e.g. "awsum 0.0.1".
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
  | -- | file, programType, target, inArg, useStdin
    CmdRun FilePath ProgramType Target (Maybe Text) Bool
  | CmdAST FilePath
  | -- | file, programType
    CmdCore FilePath ProgramType
  | -- | file, programType, target (JVM/WASM only)
    CmdAsm FilePath ProgramType Target
  | -- | file, inPlace
    CmdFormat FilePath Bool
  | -- | file, useJson
    CmdSymbols FilePath Bool
  deriving stock (Show)

-- ════════════════════════════════════════════════════════════════════════════
-- CLI parsers
-- ════════════════════════════════════════════════════════════════════════════

-- | Required positional: path to a source file.
argFilePath :: OA.Parser FilePath
argFilePath = OA.strArgument (OA.metavar "FILE")

-- | Mandatory program-type selector. Decides which platform-effect
--   table the typechecker and lowering see (see 'Awsum.Program'). We
--   deliberately require the flag rather than defaulting to @cli@:
--   once browser/module program types land, a silently-defaulted build
--   would typecheck against the wrong effect set. When @awsum.json@
--   lands, the workspace file will set this and the flag will become
--   optional.
optProgramType :: OA.Parser ProgramType
optProgramType =
  OA.option
    (OA.eitherReader (first toString . parseProgramType . toText))
    ( OA.long "program-type"
        <> OA.metavar "PROGRAM_TYPE"
        <> OA.help "Program type: cli"
        <> OA.completeWith ["cli"]
    )

-- | Optional target backend selector.
optTarget :: OA.Parser Target
optTarget =
  OA.option
    (OA.maybeReader readTarget)
    ( OA.long "target"
        <> OA.short 't'
        <> OA.metavar "TARGET"
        <> OA.help "Target backend: llvm | jvm | clr | wasm | js | lua"
        <> OA.completeWith ["llvm", "jvm", "clr", "wasm", "js", "lua"]
    )
  where
    readTarget :: String -> Maybe Target
    readTarget = \case
      "llvm" -> Just TargetLLVM
      "jvm" -> Just TargetJVM
      "clr" -> Just TargetCLR
      "wasm" -> Just TargetWASM
      "js" -> Just TargetJS
      "lua" -> Just TargetLua
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

-- | Optional: input text for 'run' (passed to 'main' when not using stdin).
optInputText :: OA.Parser (Maybe Text)
optInputText =
  optional
    ( (toText :: String -> Text)
        <$> OA.strOption
          ( OA.long "input"
              <> OA.metavar "TEXT"
              <> OA.help "Input string passed to main"
          )
    )

-- | Flag: read input for 'run' from STDIN instead of --input.
optUseStdin :: OA.Parser Bool
optUseStdin = OA.switch (OA.long "stdin" <> OA.help "Read input for main from stdin")

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
          <> subcmd "run" "Compile and run with given input" (CmdRun <$> argFilePath <*> optProgramType <*> optTarget <*> optInputText <*> optUseStdin)
          <> subcmd "ast" "Print parsed AST" (CmdAST <$> argFilePath)
          <> subcmd "core" "Print elaborated Core" (CmdCore <$> argFilePath <*> optProgramType)
          <> subcmd "asm" "Print target assembly text (jvm, wasm)" (CmdAsm <$> argFilePath <*> optProgramType <*> optTarget)
          <> subcmd "format" "Format source (render . parse)" (CmdFormat <$> argFilePath <*> optInPlace)
          <> subcmd "symbols" "Print top-level symbols (outline)" (CmdSymbols <$> argFilePath <*> optJson)
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
    core <- compileToCoreOrDie progType filePath
    -- (warnings are emitted to stderr by compileToCoreOrDie)
    case target of
      TargetJVM -> do
        let bytes = assembleJVM core
        case mOut of
          Nothing -> BS.hPut stdout bytes
          Just out -> writeFileBS out bytes
      TargetCLR -> do
        let bytes = assembleCLR core
        case mOut of
          Nothing -> BS.hPut stdout bytes
          Just out -> do
            writeFileBS out bytes
            let rcPath = dropExtension out <> ".runtimeconfig.json"
            writeFileText rcPath runtimeConfigJson
      TargetWASM -> do
        let bytes = assembleWASM core
        case mOut of
          Nothing -> BS.hPut stdout bytes
          Just out -> writeFileBS out bytes
      _ -> do
        let code = codegenText progType target core
        case mOut of
          Nothing -> putTextLn code
          Just out -> writeFileText out code
  CmdRun filePath progType target mInput useStdin -> do
    input <-
      if useStdin
        then T.stripEnd <$> TIO.getContents
        else pure (fromMaybe "" mInput)
    core <- compileToCoreOrDie progType filePath
    runOnTarget progType target core input
  CmdAST filePath -> do
    prog <- parseFileOrDie filePath
    pPrint prog
  CmdCore filePath progType -> do
    verifyPreludeOrDie progType
    userProg <- parseFileOrDie filePath
    let prog = withPrelude userProg
    case elaborateLowerProgram progType prog of
      Left err -> die $ toString (prettyPrintTypeError err)
      Right (warns, ir) -> do
        emitWarningsToStderr filePath (stripPreludeWarnings warns)
        pPrint ir
  CmdAsm filePath progType target -> do
    core <- compileToCoreOrDie progType filePath
    case target of
      TargetJVM -> putTextLn (codegenJVM core)
      TargetCLR -> putTextLn (codegenCLR core)
      TargetWASM -> putTextLn (codegenWASM core)
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

-- ════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════

-- | Select the text codegen for a target. Some targets (@JS@) are
--   parameterized by 'ProgramType' because their wrapping strategy
--   depends on it.
codegenText :: ProgramType -> Target -> CoreProgram -> Text
codegenText progType = \case
  TargetLLVM -> codegenLLVM
  TargetJVM -> codegenJVM
  TargetCLR -> codegenCLR
  TargetWASM -> codegenWASM
  TargetJS -> codegenJS progType
  TargetLua -> codegenLua

-- | Compile Core to target and run using the appropriate system runtime.
runOnTarget :: ProgramType -> Target -> CoreProgram -> Text -> IO ()
runOnTarget progType target core input = case target of
  TargetLLVM ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let llPath = dir </> "out.ll"
          binPath = dir </> "out"
      writeFileText llPath (codegenLLVM core)
      (exitClang, _, stderrClang) <- readProcessWithExitCode "clang" ["-O2", "-Wno-override-module", llPath, "-o", binPath] ""
      case exitClang of
        ExitFailure _ -> die $ toString ("clang error:\n" <> toText stderrClang)
        ExitSuccess -> do
          (exit, stdoutS, stderrS) <- readProcessWithExitCode binPath [toString input] ""
          case exit of
            ExitSuccess -> putTextLn (toText stdoutS)
            ExitFailure _ -> die $ toString ("runtime error:\n" <> toText stderrS)
  TargetJVM ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let classPath = dir </> "AwsumMain.class"
      writeFileBS classPath (assembleJVM core)
      (exit, stdoutS, stderrS) <- readProcessWithExitCode "java" ["-cp", dir, "AwsumMain", toString input] ""
      case exit of
        ExitSuccess -> putTextLn (toText stdoutS)
        ExitFailure _ -> die $ toString ("java error:\n" <> toText stderrS)
  TargetCLR ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let dllPath = dir </> "AwsumMain.dll"
          rcPath = dir </> "AwsumMain.runtimeconfig.json"
      writeFileBS dllPath (assembleCLR core)
      writeFileText rcPath runtimeConfigJson
      (exit, stdoutS, stderrS) <- readProcessWithExitCode "dotnet" [dllPath, toString input] ""
      case exit of
        ExitSuccess -> putTextLn (toText stdoutS)
        ExitFailure _ -> die $ toString ("dotnet error:\n" <> toText stderrS)
  TargetWASM ->
    withSystemTempDirectory "awsum" $ \dir -> do
      let wasmPath = dir </> "out.wasm"
      writeFileBS wasmPath (assembleWASM core)
      (exit, stdoutS, stderrS) <- readProcessWithExitCode "wasmtime" [wasmPath, toString input] ""
      case exit of
        ExitSuccess -> putTextLn (toText stdoutS)
        ExitFailure _ -> die $ toString ("wasmtime error:\n" <> toText stderrS)
  TargetJS ->
    runText "node" ".js" (codegenJS progType core) input
  TargetLua ->
    runText "lua" ".lua" (codegenLua core) input

-- | Write text code to a temp file and run with the given interpreter.
runText :: String -> String -> Text -> Text -> IO ()
runText cmd ext code input =
  withSystemTempDirectory "awsum" $ \dir -> do
    let outPath = dir </> "out" <> ext
    writeFileText outPath code
    (exit, stdoutS, stderrS) <- readProcessWithExitCode cmd [outPath, toString input] ""
    case exit of
      ExitSuccess -> putTextLn (toText stdoutS)
      ExitFailure _ -> die $ toString (toText cmd <> " error:\n" <> toText stderrS)

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
compileToCoreOrDie :: ProgramType -> FilePath -> IO CoreProgram
compileToCoreOrDie progType filePath = do
  verifyPreludeOrDie progType
  userProg <- parseFileOrDie filePath
  let prog = withPrelude userProg
  case requireMain prog of
    Left err -> dieWithTypeError filePath err
    Right () -> pass
  case elaborateLowerProgram progType prog of
    Left err -> dieWithTypeError filePath err
    Right (warns, core) -> do
      emitWarningsToStderr filePath (stripPreludeWarnings warns)
      pure core

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
  let result = case parseProgramDiagnostic src of
        Left parseErrs -> Left (map parseErrorToDiagnostic parseErrs)
        Right userProg ->
          case typecheckProgram progType (withPrelude userProg) of
            Left typeErr -> Left [typeErrorToDiagnostic typeErr]
            Right warns -> Right (map warningToDiagnostic (stripPreludeWarnings warns))
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
