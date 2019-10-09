{-# LANGUAGE OverloadedStrings #-}
module Language.Scss.Parser
  ( parse
  , parser
  , Parser
  , Value(..)
  ) where

import Control.Applicative hiding (many)
import Data.Bifunctor (first)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void
import qualified Text.Megaparsec as Parser
import Text.Megaparsec.Char


type Parser a =
  Parser.Parsec Void Text a


data Value
  = Selector Text [Value]
  | AtRule Text Text [Value]
  | Prop Text Text
  | Variable Text Text
  | MultilineComment Text
  | Comment Text
  deriving (Show)


parse :: Text -> Either String [Value]
parse =
  first Parser.errorBundlePretty . Parser.runParser parser ""


parser :: Parser [Value]
parser =
  values Parser.eof


values :: Parser () -> Parser [Value]
values =
  Parser.manyTill $
    multilineComment
     <|> comment
     <|> Parser.try atRule
     <|> Parser.try selector
     <|> propOrVar


nestedValues :: Parser [Value]
nestedValues =
  surround whitespace curlyOpen
  *> values curlyClose
  <* whitespace


selector :: Parser Value
selector = do
  name <- Parser.takeWhileP (Just "a selector")
    (\t -> t /= '{' && t /= ';' && t /= '}')
  Parser.notFollowedBy (Parser.oneOf [';', '}'])
  Selector (Text.strip name) <$> nestedValues


atRule :: Parser Value
atRule = do
  _ <- char '@'
  rule <- Parser.takeWhileP (Just "a rule") (\t -> t /= ';' && t /= ' ')
  name <- Parser.takeWhileP (Just "a rule name") (\t -> t /= ';' && t /= '{')
  maybeSemi <- optional semicolon
  case maybeSemi of
    Just _ -> do
      whitespace
      pure $ AtRule rule (Text.strip name) []
    Nothing ->
      AtRule rule (Text.strip name) <$> nestedValues


propOrVar :: Parser Value
propOrVar =
  Variable <$> (dollar *> propName) <*> propVal <|>
  Prop <$> propName <*> propVal


propName :: Parser Text
propName = do
  Parser.notFollowedBy (Parser.oneOf ['&', '>', '~', '+'])
  Parser.takeWhileP (Just "a prop name") (\t -> t /= ':' && t /= ' ')
    <* surround whitespace colon


propVal :: Parser Text
propVal = do
  v <- Parser.takeWhileP (Just "a prop value")
    (\t -> t /= '#' && t /= '}' && t /= ';')
  isHash <- optional (char '#')
  case isHash of
    Nothing -> do
      surround whitespace (semicolon <|> Parser.lookAhead curlyClose)
      pure (Text.stripEnd v)
    Just _ -> do
      rest <- (mappend <$> hashVar <*> propVal) <|> propVal
      pure (Text.stripStart v <> "#" <> rest)


hashVar :: Parser Text
hashVar =
  (\a b c -> a <> b <> c)
  <$> Parser.chunk "{"
  <*> Parser.takeWhileP (Just "a hash var") (/= '}')
  <*> Parser.chunk "}"


multilineComment :: Parser Value
multilineComment = do
  _ <- Parser.chunk "/*"
  c <- Parser.takeWhileP (Just "a multiline comment") (/= '*')
  closing <- optional (Parser.chunk "*/")
  case closing of
    Nothing ->
      multilineComment
    Just _ -> do
      whitespace
      pure (MultilineComment c)


comment :: Parser Value
comment = do
  _ <- Parser.chunk "//"
  c <- Parser.takeWhileP (Just "a comment") (/= '\n')
  whitespace
  pure (Comment c)


semicolon :: Parser ()
semicolon =
  () <$ char ';'


colon :: Parser ()
colon =
  () <$ char ':'


curlyOpen :: Parser ()
curlyOpen =
  () <$ char '{'


curlyClose :: Parser ()
curlyClose =
  () <$ char '}'


dollar :: Parser ()
dollar =
  () <$ char '$'


whitespace :: Parser ()
whitespace =
  space <|> () <$ eol <|> () <$ newline


surround :: Parser a -> Parser b -> Parser b
surround a b =
  a *> b <* a
