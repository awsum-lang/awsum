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
import Awsum.ElaborateLower (elaborateLowerProgram)
import Awsum.Format (formatSource)
import Awsum.Parser (parseProgramDiagnostic)
import Awsum.Symbols (symbolsOfProgram, symbolsToJson)
import Awsum.Syntax
import Awsum.Typing (TypeError, prettyPrintTypeError, typeErrorSpan, typecheckProgram)
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
data Command
  = CmdVersion
  | -- | file, useJson
    CmdCheck FilePath Bool
  | -- | file, target, out
    CmdBuild FilePath Target (Maybe FilePath)
  | -- | file, target, inArg, useStdin
    CmdRun FilePath Target (Maybe Text) Bool
  | CmdAST FilePath
  | CmdCore FilePath
  | -- | file, target (JVM/WASM only)
    CmdAsm FilePath Target
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
      ( subcmd "check" "Parse and typecheck a file" (CmdCheck <$> argFilePath <*> optJson)
          <> subcmd "build" "Compile file to target language" (CmdBuild <$> argFilePath <*> optTarget <*> optOutputPath)
          <> subcmd "run" "Compile and run with given input" (CmdRun <$> argFilePath <*> optTarget <*> optInputText <*> optUseStdin)
          <> subcmd "ast" "Print parsed AST" (CmdAST <$> argFilePath)
          <> subcmd "core" "Print elaborated Core" (CmdCore <$> argFilePath)
          <> subcmd "asm" "Print target assembly text (jvm, wasm)" (CmdAsm <$> argFilePath <*> optTarget)
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
  CmdCheck filePath useJson
    | useJson -> do
        src <- readFileTextUtf8 filePath
        case parseProgramDiagnostic src of
          Left parseErrs -> do
            putTextLn (diagnosticsToJson [(sp, msg) | (sp, msg) <- parseErrs])
            exitFailure
          Right prog ->
            case typecheckProgram prog of
              Left typeErr -> do
                let sp = fromMaybe (SrcSpan 1 1 1 1) (typeErrorSpan typeErr)
                putTextLn (diagnosticsToJson [(sp, prettyPrintTypeError typeErr)])
                exitFailure
              Right () -> putTextLn "[]"
    | otherwise -> do
        prog <- parseFileOrDie filePath
        case typecheckProgram prog of
          Left err -> dieWithTypeError filePath err
          Right () -> putTextLn "OK"
  CmdBuild filePath target mOut -> do
    core <- compileToCoreOrDie filePath
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
        let code = codegenText target core
        case mOut of
          Nothing -> putTextLn code
          Just out -> writeFileText out code
  CmdRun filePath target mInput useStdin -> do
    input <-
      if useStdin
        then T.stripEnd <$> TIO.getContents
        else pure (fromMaybe "" mInput)
    core <- compileToCoreOrDie filePath
    runOnTarget target core input
  CmdAST filePath -> do
    prog <- parseFileOrDie filePath
    pPrint prog
  CmdCore filePath -> do
    prog <- parseFileOrDie filePath
    case elaborateLowerProgram prog of
      Left err -> die $ toString (prettyPrintTypeError err)
      Right ir -> pPrint ir
  CmdAsm filePath target -> do
    core <- compileToCoreOrDie filePath
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

-- | Select the text codegen for a target.
codegenText :: Target -> CoreProgram -> Text
codegenText = \case
  TargetLLVM -> codegenLLVM
  TargetJVM -> codegenJVM
  TargetCLR -> codegenCLR
  TargetWASM -> codegenWASM
  TargetJS -> codegenJS
  TargetLua -> codegenLua

-- | Compile Core to target and run using the appropriate system runtime.
runOnTarget :: Target -> CoreProgram -> Text -> IO ()
runOnTarget target core input = case target of
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
    runText "node" ".js" (codegenJS core) input
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
compileToCoreOrDie :: FilePath -> IO CoreProgram
compileToCoreOrDie filePath = do
  prog <- parseFileOrDie filePath
  case elaborateLowerProgram prog of
    Left err -> dieWithTypeError filePath err
    Right core -> pure core

-- | Read a file as UTF-8 and parse a 'Program' or terminate with an error.
parseFileOrDie :: FilePath -> IO Program
parseFileOrDie filePath = do
  text <- readFileTextUtf8 filePath
  case parseProgramDiagnostic text of
    Left diags -> dieWithDiagnostics filePath diags
    Right p -> pure p

-- | Report a 'TypeError' with the offending source line shown, Scala-style:
--   a @-- Error: path:line:col@ header that VS Code's terminal link provider
--   picks up as a clickable link, then the source line with a caret indicator
--   and the error message.
dieWithTypeError :: FilePath -> TypeError -> IO a
dieWithTypeError filePath err =
  dieWithDiagnostics filePath [(fromMaybe (SrcSpan 1 1 1 1) (typeErrorSpan err), prettyPrintTypeError err)]

-- | Render and print diagnostics, then exit with a non-zero status.
--   Re-reads the source file so the offending line can be shown verbatim.
--   Emits ANSI colour when stderr is a terminal and @NO_COLOR@ is unset
--   (the @NO_COLOR@ convention: <https://no-color.org>).
dieWithDiagnostics :: FilePath -> [(SrcSpan, Text)] -> IO a
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

-- | Format diagnostics in Scala-style:
--
-- @
-- -- Error: path/to/file.aww:8:11
-- 8 |overMax = 256
--   |          ^^^
--   |          Integer literal 256 out of range for UInt8 (valid range: 0..255)
-- @
--
-- Multiple diagnostics are separated by a blank line.  When @useColor@ is
-- true, the header line and the caret markers are rendered in bold red.
formatDiagnostics :: Bool -> FilePath -> Text -> [(SrcSpan, Text)] -> Text
formatDiagnostics useColor filePath source = T.intercalate "\n\n" . map formatOne
  where
    sourceLines = lines source

    boldRed :: Text -> Text
    boldRed t = if useColor then "\ESC[1;31m" <> t <> "\ESC[0m" else t

    red :: Text -> Text
    red t = if useColor then "\ESC[31m" <> t <> "\ESC[0m" else t

    formatOne :: (SrcSpan, Text) -> Text
    formatOne (SrcSpan sl sc el ec, msg) =
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
          header = boldRed ("-- Error: " <> toText filePath <> ":" <> show sl <> ":" <> show sc)
          msgIndent = emptyGutter <> caretIndent
          -- Some diagnostics (notably Megaparsec parse errors) include newlines;
          -- indent every continuation line so the gutter stays aligned.
          indentedMsg = T.intercalate ("\n" <> msgIndent) (lines msg)
       in T.intercalate
            "\n"
            [ header,
              gutter <> lineText,
              emptyGutter <> caretIndent <> red carets,
              msgIndent <> indentedMsg
            ]

-- ════════════════════════════════════════════════════════════════════════════
-- JSON diagnostics (hand-written, no aeson dependency)
-- ════════════════════════════════════════════════════════════════════════════

-- | Render diagnostics as a JSON array.
diagnosticsToJson :: [(SrcSpan, Text)] -> Text
diagnosticsToJson errs = "[" <> T.intercalate "," (map diagToJson errs) <> "]"

diagToJson :: (SrcSpan, Text) -> Text
diagToJson (SrcSpan sl sc el ec, msg) =
  "{\"startLine\":"
    <> show sl
    <> ",\"startCol\":"
    <> show sc
    <> ",\"endLine\":"
    <> show el
    <> ",\"endCol\":"
    <> show ec
    <> ",\"message\":"
    <> jsonString msg
    <> "}"

-- | Escape a text value for JSON string embedding.
jsonString :: Text -> Text
jsonString t = "\"" <> T.concatMap escapeJsonChar t <> "\""

escapeJsonChar :: Char -> Text
escapeJsonChar = \case
  '"' -> "\\\""
  '\\' -> "\\\\"
  '\n' -> "\\n"
  '\r' -> "\\r"
  '\t' -> "\\t"
  c -> one c
