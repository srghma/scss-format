{-# LANGUAGE OverloadedStrings #-}

module Language.Scss.Parser
  ( parse,
    parser,
    Parser,
    Value (..),
  )
where

import Control.Applicative hiding (many)
import Data.Bifunctor (first)
import Data.Foldable (asum)
import Data.Functor (void)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Void
import qualified Text.Megaparsec as Parser
import Text.Megaparsec.Char
import Debug.Trace

type Parser a =
  Parser.Parsec Void Text a

data Value
  = Selector         Text [Value]
  | AtRule           Text Text [Value]
  | Prop             Text Text
  | Variable         Text Text
  | MultilineComment Text
  | Comment          Text
  deriving (Show)

parse :: Text -> Either String [Value]
parse =
  first Parser.errorBundlePretty . Parser.runParser parser ""

parser :: Parser [Value]
parser =
  ws *> values Parser.eof

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
  curlyOpen *> values curlyClose

selector :: Parser Value
selector =
  let nameParser =
        Parser.takeWhileP
          (Just "a selector")
          (\t -> t /= '#' && t /= '{' && t /= ';' && t /= '}')
   in do
        name <- nameParser
        more <-
          asum
            [ do
                _ <- char '#'
                rest <- (mappend <$> hashVar <*> nameParser) <|> nameParser
                pure $ Text.stripStart name <> "#" <> Text.strip rest,
              do
                pure $ Text.strip name
            ]
        Parser.notFollowedBy (Parser.satisfy (\t -> t == ';' || t == '}'))
        Selector more <$> nestedValues

atRule :: Parser Value
atRule = do
  _ <- char '@'
{-
  rule <- Parser.takeWhileP (Just "at rule") (\t -> t /= ';' && t /= ' ')
  _ <- char ' '
  body <- parseAtRuleBody
  maybeSemi <- optional semicolon
  case maybeSemi of
    Just _ -> do
      whitespace
      pure $ AtRule rule (Text.strip body) []
    Nothing ->
      AtRule rule (Text.strip body) <$> nestedValues

parseAtRuleBody :: Parser Text
parseAtRuleBody = Parser.label "at rule body" $
  Text.concat <$> Parser.many nameIdents
      where
        nameIdents =
          string "#{"
          <|> (Text.singleton <$> otherNameIdentChars)

        otherNameIdentChars = Parser.satisfy (\t -> t /= ';' && t /= '{') Parser.<?> "non ';' or '{' (but allow '#{')"
-}
  rule <- Parser.takeWhileP (Just "at rule") (\t -> t /= '{' && t /= ';' && t /= ' ')
  name <- parseAtRuleName
  lexe $
    asum
      [ AtRule rule (Text.strip name) [] <$ Parser.try semicolon,
        AtRule rule (Text.strip name) <$> nestedValues
      ]

parseAtRuleName :: Parser Text
parseAtRuleName = do
  v1 <- Parser.takeWhileP (Just "at rule name") (\t -> t /= ';' && t /= '{' && t /= '#')
  lexe $
    asum
      [ do
          hash <- Parser.try (lexe (Parser.chunk "#{"))
          v2 <- parseAtRuleName
          pure (v1 <> hash <> v2),
        pure v1
      ]

propOrVar :: Parser Value
propOrVar =
  Variable <$> (dollar *> propName) <*> propVal
    <|> Prop <$> propName <*> propVal

propName :: Parser Text
propName = do
  Parser.notFollowedBy (Parser.satisfy (\t -> t == '&' || t == '>' || t == '~' || t == '+'))
  Parser.takeWhileP (Just "a prop name") (\t -> t /= ':' && t /= ' ')
    <* surround ws colon

propVal :: Parser Text
propVal = do
  v <- Parser.takeWhileP (Just "a prop value") (\t -> t /= '#' && t /= '}' && t /= ';')
  lexe $
    asum
      [ do
          _ <- char '#'
          rest <- (mappend <$> hashVar <*> propVal) <|> propVal
          pure (Text.stripStart v <> "#" <> rest),
        do
          _ <- Parser.chunk ";base64"
          rest <- Parser.takeWhileP (Just "a base64 value") (\t -> t /= '}' && t /= ';')
          lexe (semicolon <|> Parser.lookAhead curlyClose)
          pure (Text.stripEnd v <> ";base64" <> Text.stripEnd rest),
        do
          lexe (semicolon <|> Parser.lookAhead curlyClose)
          pure (Text.stripEnd v)
      ]

hashVar :: Parser Text
hashVar = do
  (\a b c -> a <> b <> c)
    <$> Parser.chunk "{"
    <*> Parser.takeWhileP (Just "a hash var") (/= '}')
    <*> Parser.chunk "}"

multilineComment :: Parser Value
multilineComment =
  let parseLine = do
        value <- Parser.takeWhileP (Just "a multiline comment") (/= '*')
        asum
          [ value <$ Parser.try (Parser.chunk "*/"),
            do
              char '*'
              mappend (value <> "*") <$> parseLine
          ]
   in do
        _ <- Parser.chunk "/*"
        MultilineComment <$> lexe parseLine

comment :: Parser Value
comment = do
  _ <- Parser.chunk "//"
  lexe $ Comment <$> Parser.takeWhileP (Just "a comment") (/= '\n')

semicolon :: Parser ()
semicolon =
  () <$ lexe (char ';')

colon :: Parser ()
colon =
  () <$ lexe (char ':')

curlyOpen :: Parser ()
curlyOpen =
  () <$ lexe (char '{')

curlyClose :: Parser ()
curlyClose =
  () <$ lexe (char '}')

dollar :: Parser ()
dollar =
  () <$ lexe (char '$')

surround :: Parser a -> Parser b -> Parser b
surround a b =
  a *> b <* a

lexe :: Parser a -> Parser a
lexe =
  (<* ws)

ws :: Parser ()
ws =
  space <|> void eol <|> void newline
