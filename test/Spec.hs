{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.HashMap.Strict as HM
import Data.Sajson
import Data.Scientific
import qualified Data.Text as T
import qualified Data.Vector as V
import Test.Hspec
import Test.Hspec.Core.Runner
import Test.QuickCheck

newtype AcceptableValue = AcceptableValue { getAcceptableValue :: Value } deriving (Show, Eq)

instance Arbitrary AcceptableValue where
  arbitrary = AcceptableValue <$> oneof [Array <$> genArray, Object <$> genObject]
      where genText = T.pack <$> listOf (oneof [choose (' ', '~'), choose ('\256', '\383'), choose ('\19968', '\40959'), choose ('\128512', '\128591')]) -- latin text, CJK ideographs, and emoji
            genNumber = fromIntegral <$> choose (-9007199254740992, 9007199254740992 :: Int)
            genArray = V.fromList <$> reducedSize (listOf genValue)
            genObject = HM.fromList <$> reducedSize (listOf ((,) <$> genText <*> genValue))
            genValue = oneof [Number <$> genNumber, pure Null, Bool <$> arbitrary, String <$> genText, Array <$> genArray, Object <$> genObject]
            reducedSize = scale (`div` 2)

main :: IO ()
main = hspecWith defaultConfig { configQuickCheckMaxSuccess = Just 5000 } $ do
  describe "sajsonParse" $ do
    it "returns proper error for truncated JSON document" $ do
      r <- sajsonParse "{\"abc\":123,\"def\":[1,2,3"
      r `shouldBe` Left SajsonParseError {sajsonParseErrorLine = 1, sajsonParseErrorColumn = 24, sajsonParseErrorMessage = "unexpected end of input"}
    describe "returns Right for correct JSON document" $ do
      it "object of null" $ do
        r <- sajsonParse "{\"abc\":null}"
        r `shouldBe` Right (object ["abc" .= Null])
      it "object of true" $ do
        r <- sajsonParse "{\"abc\":true}"
        r `shouldBe` Right (object ["abc" .= Bool True])
      it "object of false" $ do
        r <- sajsonParse "{\"abc\":false}"
        r `shouldBe` Right (object ["abc" .= Bool False])
      it "object of integer" $ do
        r <- sajsonParse "{\"abc\":2147483647}"
        r `shouldBe` Right (object ["abc" .= Number 2147483647])
      it "object of double" $ do
        r <- sajsonParse "{\"abc\":3.141592653589793}"
        r `shouldBe` Right (object ["abc" .= Number 3.141592653589793])
      it "object of big integer (exponential notation)" $ do
        r <- sajsonParse "{\"abc\":1e308}"
        r `shouldBe` Right (object ["abc" .= Number (scientific 1 308)])
      it "object of array of number" $ do
        r <- sajsonParse "{\"abc\":[1,2,3],\"def\":[0.1,0.2]}"
        r `shouldBe` Right (object ["abc" .= [1.0 :: Scientific, 2.0, 3.0], "def" .= [0.1 :: Scientific, 0.2]])
    it "round trips acceptable values with aeson" $ property $ \(AcceptableValue v) -> ioProperty $ do
      let encoded = encode v
      decoded <- sajsonParse (BL.toStrict encoded)
      decoded `shouldBe` Right v
      pure True
