{-# language ViewPatterns #-}
-- | This module is both the place for testing Utils and for providing utility functions for
-- the testsuite (admittedly unelegant)

module Utils.Tests where


import Data.List
import Data.Maybe

import Utils

import Test.QuickCheck


tests :: IO ()
tests = testMergePairs

testMergePairs :: IO ()
testMergePairs = mapM_ (quickCheckWith stdArgs{maxSuccess = 1000}) [
    putTestCase "testMergePairs.isIdempotent" $ \ l -> isIdempotent l (mergePairs testPredicate),
    putTestCase "testMergePairs.reversal" $ \ (map abs -> l) ->
        null (mergePairs testPredicate l \\ mergePairs testPredicate (reverse l)),
    putTestCase "testMergePairs.done all" $ \ l -> all isNothing $ map (uncurry testPredicate) $
        completeEdges $ mergePairs testPredicate l
   ]

testPredicate :: Int -> Int -> Maybe [Int]
testPredicate a b | a == 0 = Nothing
testPredicate a b = if b `mod` a == 0 then Just [a] else Nothing


-- * these are test Utils (not tests for the Utils module)

isIdempotent :: Eq a => a -> (a -> a) -> Bool
isIdempotent x f =
    fx == f fx
  where
    fx = f x

-- | attaches a message to a property that will be printed in case of failure
putTestCase :: Testable p => String -> p -> Property
putTestCase msg p = whenFail (putStrLn msg) p

-- | executes a test only once
quickCheckOnce :: Testable p => p -> IO ()
quickCheckOnce = quickCheckWith stdArgs{maxSuccess = 1}

-- | tests a list of possible offending values
testExamples :: Testable p => String -> (a -> p) -> [a] -> IO ()
testExamples msg p examples =
    mapM_ (\ (i, example) -> quickCheckOnce $
        putTestCase (msg ++ " element no.: " ++ show i) $
        p example)
        (zip [0..] examples)