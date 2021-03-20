module Replica.App.Run

import Control.ANSI
import Control.App
import Control.App.Console

import Data.List
import Data.Maybe
import Data.String

import Language.JSON

import System.Future

import Replica.App.FileSystem
import Replica.App.Log
import Replica.App.Replica
import Replica.App.Run.Dependencies
import Replica.App.System

import Replica.Command.Run
import Replica.Core.Parse
import Replica.Core.Types
import Replica.Option.Global
import Replica.Other.String
import Replica.Other.Validation

%default total

data RunContext : Type where

ok : State GlobalConfig GlobalOption e => App e String
ok = do
  ascii <- map ascii $ get GlobalConfig
  pure $ if ascii then "OK " else "✅ "

ko : State GlobalConfig GlobalOption e => App e String
ko = do
  ascii <- map ascii $ get GlobalConfig
  pure $ if ascii then "KO " else "❌ "

err : State GlobalConfig GlobalOption e => App e String
err = do
  ascii <- map ascii $ get GlobalConfig
  pure $ if ascii then "ERR" else "⚠️ "

bold : State GlobalConfig GlobalOption e => App e (String -> String)
bold = do
  c <- map colour $ get GlobalConfig
  pure $ if c then (show . bolden) else id


yellow : State GlobalConfig GlobalOption e => App e (String -> String)
yellow = do
  c <- map colour $ get GlobalConfig
  pure $ if c then (show . colored Yellow) else id


red : State GlobalConfig GlobalOption e => App e (String -> String)
red = do
  c <- map colour $ get GlobalConfig
  pure $ if c then (show . colored Red) else id


prepareReplicaDir : SystemIO (SystemError :: e) =>
  FileSystem (FSError :: e) =>
  Has [ State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Exception ReplicaError
      , Console
      ] e => App e String
prepareReplicaDir = do
  debug $ "GlobalConfig: \{!(map show $ get GlobalConfig)}"
  handle setAbsoluteReplicaDir
    pure
    (\err : FSError => throw $ CantAccessTestFile "current directory")
  rDir <- getReplicaDir
  log "Replica directory: \{rDir}"
  handle (system "mkdir -p \{show (testDir rDir)}")
    pure
    (\err : SystemError => throw $ CantAccessTestFile "\{show (testDir rDir)}")
  pure rDir

runAll :
  SystemIO (SystemError :: e) =>
  State GlobalConfig GlobalOption e =>
  Exception TestError e =>
  Console e =>
  (phase : Maybe String) ->
  (String -> TestError) ->
  List String -> App e ()
runAll phase liftError [] = pure ()
runAll phase liftError (x :: xs) = do
  maybe (pure ()) (\p => log "\{p}: \{x}") phase
  handle (system x)
    (const $ runAll phase liftError xs)
    (\err : SystemError => throw $ liftError x)

expectedVsGiven : Console e => Maybe String -> String -> App e ()
expectedVsGiven old given = do
  case old of
       Nothing => putStrLn "Expected: Nothing Found"
       Just str => do
         putStrLn "Expected:"
         putStrLn str
  putStrLn "Given:"
  putStrLn given

askForNewGolden : FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State GlobalConfig GlobalOption
      , Exception TestError
      , Console
      ] e => Maybe String -> String -> App e TestResult
askForNewGolden old given = do
  t <- get CurrentTest
  putStrLn $ "\{t.name}: Golden value mismatch"
  expectedVsGiven old given
  putStrLn $ "Do you want to " ++ maybe "set" (const "replace") old ++ " the golden value? [N/y]"
  if !readAnswer
     then do
       expectedFile <- handle getExpectedFile pure
          (\err : FSError => throw $ FileSystemError
             "Can't resolve expectation file")
       handle (writeFile expectedFile given)
         (const $ pure Success)
         (\err : FSError => throw $ FileSystemError "Cannot write golden value")
     else pure $ maybe (Fail [WrongOutput GoldenIsMissing])
                       (Fail . pure . WrongOutput . flip DifferentOutput given)
                       old
  where
    readAnswer : App e Bool
    readAnswer = do
      answer <- getLine
      pure $ toLower answer `elem` ["y", "yes"]

checkOutput : FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State GlobalConfig GlobalOption
      , State RunContext RunAction
      , Exception TestError
      , Console ] e =>
  (mustSucceed : Maybe Bool) -> (status : Int) ->
  (expectedOutput : Maybe String) -> (output : String) ->
  App e TestResult
checkOutput mustSucceed status expectedOutput output
  = do
    ctx <- get RunContext
    case checkExpectation of
         Success => pure $ checkStatus
         Fail err => case checkStatus of
            Fail err2 => pure $ Fail $ err ++ err2
            Success => if ctx.interactive
              then askForNewGolden expectedOutput output
              else pure $ Fail err
    where
      checkStatus : TestResult
      checkStatus = maybe
        Success
        (\s => if (s && status == 0) || (not s && status /= 0)
                  then Success
                  else Fail [WrongStatus s])
        mustSucceed
      checkExpectation : TestResult
      checkExpectation = maybe
        (Fail [WrongOutput GoldenIsMissing])
        (\exp => if exp == output
          then Success
          else Fail [WrongOutput $ DifferentOutput exp output])
        expectedOutput

getExpected : FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State GlobalConfig GlobalOption
      , State RunContext RunAction
      , Exception TestError
      , Console
      ] e => String -> App e (Maybe String)
getExpected given = do
  t <- get CurrentTest
  expectedFile <- getExpectedFile
  handle (readFile expectedFile)
    (pure . Just)
    (\err : FSError => case err of
        MissingFile _ => pure Nothing
        err => throw $ FileSystemError "Cannot read expectation")

testCore : SystemIO (SystemError :: e) =>
  FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State GlobalConfig GlobalOption
      , State RunContext RunAction
      , Exception TestError
      , Console
      ] e => App e TestResult
testCore = do
  t <- get CurrentTest
  outputFile <- getOutputFile
  exitStatus <- handle (system $ "\{t.command} > \"\{outputFile}\"")
    (const $ pure 0)
    (\(Err n) => pure n)
  output <- handle (readFile $ outputFile) pure
    (\e : FSError => throw $
          FileSystemError "Can't read output file \{outputFile}")
  expected <- getExpected output
  checkOutput t.mustSucceed exitStatus expected output

performTest : SystemIO (SystemError :: e) =>
  FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State GlobalConfig GlobalOption
      , State RunContext RunAction
      , Exception TestError
      , Console
      ] e => App e TestResult
performTest = do
  t <- get CurrentTest
  runAll (Just "Before") InitializationFailed t.beforeTest
  log $ withOffset 2 "Running command: \{t.command}"
  res <- testCore
  runAll (Just "After") (WrapUpFailed res) t.afterTest
  pure res

runTest : SystemIO (SystemError :: e) =>
  FileSystem (FSError :: e) =>
  Has [ State CurrentTest Test
      , State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Exception TestError
      , Console
      ] e => App e TestResult
runTest = do
  ctx <- get RunContext
  t <- get CurrentTest
  let wd = fromMaybe (ctx.workingDir) t.workingDir
  log "Executing \{t.name}"
  debug $ withOffset 2 $ show t
  log $ withOffset 2 "Working directory: \{show wd}"
  handle (inDir wd performTest)
    pure
    (\err : FSError => throw $ FileSystemError
      "Error: cannot enter or exit test working directory \{show wd}")

runAllTests : SystemIO (SystemError :: TestError :: e) =>
  SystemIO (SystemError :: e) =>
  FileSystem (FSError :: TestError :: e) =>
  Console (TestError :: e) =>
  Has [ State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Console
      ] e =>  TestPlan -> App e (List (String, Either TestError TestResult))
runAllTests plan = do
  putStrLn $ separator 60
  putStrLn $ !bold "Running tests..."
  batchTests [] plan
  where
    processTest : Test -> App e (String, Either TestError TestResult)
    processTest x = do
      rdir <- getReplicaDir
      r <- handle
             (new x runTest)
             (pure . MkPair x.name . Right)
             (\err : TestError => pure (x.name, Left err))
      pure r
    prepareBatch : Nat -> TestPlan -> (List Test, List Test)
    prepareBatch n plan = if n == 0 then (plan.now, Prelude.Nil) else splitAt n plan.now
    processResult : TestPlan -> (String, Either TestError TestResult) -> TestPlan
    processResult plan (tName, (Right Success)) = validate tName plan
    processResult plan (tName, _) = fail tName plan
    isSuccess : Either TestError TestResult -> Bool
    isSuccess (Right Success) = True
    isSuccess _ = False
    batchTests : List (String, Either TestError TestResult) ->
                 TestPlan -> App e (List (String, Either TestError TestResult))
    batchTests acc plan = do
      n <- map threads $ get RunContext
      case prepareBatch n plan of
           ([], later) => pure $ join
              [ acc
              , map (\t => (t.name, Left Inaccessible)) plan.later
              , map (\(reason, t) => (t.name, Left $ RequirementsFailed reason)) plan.skipped
              ]
           (now, nextBatches) => do
             res <- map await <$> traverse (map (fork . delay) . processTest) now
             p <- map punitive $ get RunContext
             if p && any (not . isSuccess . snd) res
                then pure res
                else do
                   let plan' = record {now = nextBatches} plan
                   debug $ displayPlan plan'
                   batchTests (acc ++ res) $ assert_smaller plan (foldl processResult plan' res)

testOutput :
  Has [ State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Console
      ] e => String -> Either TestError TestResult -> App e ()
testOutput name x = do
  putStr $ withOffset 2 ""
  case x of
       Left y => putStr (!yellow "\{!err} \{name}: ") >> putStrLn (show y)
       Right Success => putStrLn "\{!ok} \{name}"
       Right (Fail xs) => putStrLn $ !red "\{!ko} \{name}: \{unwords $ map show xs}"

report : Console e => State GlobalConfig GlobalOption e => Stats -> App e ()
report x = do
  putStrLn $ separator 60
  putStrLn $ !bold "Summary:"
  let nb = countTests x
  if nb == 0
     then putStrLn $ withOffset 2 "No test"
     else putStrLn $ unlines $ catMaybes
    [ guard (x.successes > 0) $>
        withOffset 2 "\{!ok} (Success): \{show x.successes} / \{show nb}"
    , guard (x.failures > 0) $>
        withOffset 2 "\{!ko} (Failure): \{show x.failures} / \{show nb}"
    , guard (x.errors > 0) $>
        withOffset 2 "\{!err}  (Errors): \{show x.errors} / \{show nb}"
    ]

export
defineActiveTests : FileSystem (FSError :: e) =>
  Has [ State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Exception ReplicaError
      , Console
      ] e => App e TestPlan
defineActiveTests = do
  repl <- getReplica RunContext file
  selectedTests <- map only $ get RunContext
  excludedTests <- map exclude $ get RunContext
  selectedTags <- map onlyTags $ get RunContext
  excludedTags <- map excludeTags $ get RunContext
  debug $ "Tags: \{show selectedTags}"
  debug $ "Names: \{show selectedTests}"
  let tests = filter (go selectedTags selectedTests excludedTags excludedTests) repl.tests
  pure $ buildPlan tests
  where
    go : (tags, names, negTags, negNames : List String) -> Test -> Bool
    go tags names negTags negNames t =
      (null tags || not (null $ intersect t.tags tags))
      && (null names || (t.name `elem` names))
      && (null negTags || (null $ intersect t.tags negTags))
      && (null negNames || (not $ t.name `elem` negNames))


export
runReplica : SystemIO (SystemError :: TestError :: e) =>
  SystemIO (SystemError :: e) =>
  FileSystem (FSError :: TestError :: e) =>
  FileSystem (FSError :: e) =>
  Console (TestError :: e) =>
  Has [ State RunContext RunAction
      , State GlobalConfig GlobalOption
      , Exception ReplicaError
      , Console
      ] e => App e Stats
runReplica = do
  debug $ "Command: \{show !(get RunContext)}"
  rDir <- prepareReplicaDir
  plan <- defineActiveTests
  log $ displayPlan plan
  result <- runAllTests plan
  putStrLn $ separator 60
  putStrLn $ !bold "Test results:"
  traverse_ (uncurry testOutput) result
  let stats = asStats $ map snd result
  report $ stats
  pure stats
