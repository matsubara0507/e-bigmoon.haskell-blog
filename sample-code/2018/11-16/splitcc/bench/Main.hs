import           Data.Char          (isSpace, isUpper)
import           Data.List.Split    (split, startsWithOneOf)

import           Gauge.Main
import           Gauge.Main.Options

import           Test.QuickCheck

ansSplit :: String -> String
ansSplit = unwords . split (startsWithOneOf ['A'..'Z'])

ansFold :: String -> String
ansFold = fmt . foldr go []
  where
    go c acc
      | isUpper c = ' ':c:acc
      | otherwise = c:acc
    fmt cs
      | null cs = cs
      | isSpace (head cs) = tail cs
      | otherwise = cs

-- bench
main :: IO ()
main = do
  let conf = defaultConfig { displayMode = Condensed }
  sampleData1 <- generate $ vectorOf 10 charGen
  sampleData2 <- generate $ vectorOf 1000 charGen
  sampleData3 <- generate $ vectorOf 100000 charGen
  sampleData4 <- generate $ vectorOf 10000000 charGen

  defaultMainWith conf
    [ bgroup "ansSplit" [ bench "10" $ whnf ansSplit sampleData1
                        , bench "1000" $ whnf ansSplit sampleData2
                        , bench "100000" $ whnf ansSplit sampleData3
                        , bench "10000000" $ whnf ansSplit sampleData4
                        ]
    , bgroup "ansFold"  [ bench "10" $ whnf ansFold sampleData1
                        , bench "1000" $ whnf ansFold sampleData2
                        , bench "100000" $ whnf ansFold sampleData3
                        , bench "10000000" $ whnf ansFold sampleData4
                        ]
    ]

charGen :: Gen Char
charGen = elements (['a'..'z']++['A'..'Z'])
