interface Parser.Core
  exposes [
    Parser,
    RawStr,
    runPartialRaw,
    runPartialStr,
    runRaw,
    runStr,
    fail,
    const,
    alt,
    apply,
    andThen,
    oneOf,
    map,
    map2,
    map3,
    lazy,
    maybe,
    oneOrMore,
    many,
    between,
    sepBy,
    sepBy1,
    codepoint,
    stringRaw,
    string,
    scalar,
    betweenBraces, # An example
  ]
  imports []



## Opaque type for a parser that will try to parse an `a` from an `input`.
##
## As a simple example, you might consider a parser that tries to parse a `U32` from a `Str`.
## Such a process might succeed or fail, depending on the current value of `input`.
##
## As such, a parser can be considered a recipe
## for a function of the type `input -> Result {val: a, input: input} [ParsingFailure Str]`.
##
## How a parser is _actually_ implemented internally is not important
## and this might change between versions;
## for instance to improve efficiency or error messages on parsing failures.
Parser input a := (input -> Result {val: a, input: input} [ParsingFailure Str])

# -- Generic parsers:

## Most general way of running a parser.
##
## Can be tought of turning the recipe of a parser into its actual parsing function
## and running this function on the given input.
##
## Many (but not all!) parsers consume part of `input` when they succeed.
## This allows you to string parsers together that run one after the other:
## The part of the input that the first parser did not consume, is used by the next parser.
## This is why a parser returns on success both the resulting value and the leftover part of the input.
##
## Of course, this is mostly useful when creating your own internal parsing building blocks.
## `run` or `Parser.Str.runStr` etc. are more useful in daily usage.
runPartial : Parser input a, input -> Result {val: a, input: input} [ParsingFailure Str]
runPartial = \@Parser parser, input ->
  (parser input)

## Runs a parser on the given input, expecting it to fully consume the input
##
## The `input -> Bool` parameter is used to check whether parsing has 'completed',
## (in other words: Whether all of the input has been consumed.)
##
## For most (but not all!) input types, a parsing run that leaves some unparsed input behind
## should be considered an error.
run : Parser input a, input, (input -> Bool) -> Result a [ParsingFailure Str, ParsingIncomplete input]
run = \parser, input, isParsingCompleted ->
  when (runPartial parser input) is
    Ok {val: val, input: leftover} ->
      if isParsingCompleted leftover then
        Ok val
      else
        Err (ParsingIncomplete leftover)
    Err (ParsingFailure msg) ->
      Err (ParsingFailure msg)

## Parser that can never succeed, regardless of the given input.
## It will always fail with the given error message.
##
## This is mostly useful as 'base case' if all other parsers
## in a `oneOf` or `alt` have failed, to provide some more descriptive error message.
fail : Str -> Parser * *
fail = \msg ->
  @Parser \_input -> Err (ParsingFailure msg)

## Parser that will always produce the given `val`, without looking at the actual input.
## This is useful as basic building block, especially in combination with
## `map` and `apply`.
const : a -> Parser * a
const = \val ->
  @Parser \input ->
    Ok { val: val, input: input }

## Try the `left` parser and (only) if it fails, try the `right` parser as fallback.
alt : Parser input a, Parser input a -> Parser input a
alt = \left, right ->
  fun = \input ->
    when (runPartial left input) is
      Ok {val: val, input: rest} -> Ok {val: val, input: rest}
      Err (ParsingFailure leftErr) ->
        when (runPartial right input) is
        Ok {val: val, input: rest} -> Ok {val: val, input: rest}
        Err (ParsingFailure rightErr) ->
          Err (ParsingFailure ("\(leftErr) or \(rightErr)"))
  @Parser fun

#  applyOld : Parser input a, Parser input (a -> b) -> Parser input b
#  applyOld = \valParser, funParser ->
#    combined = \input ->
#      {val: val, input: rest} <- Result.after (runPartial valParser input)
#      (runPartial funParser rest)
#      |> Result.map \{val: funVal, input: rest2} ->
#        {val: funVal val, input: rest2}
#    @Parser combined

## Runs a parser building a function, then a parser building a value,
## and finally returns the result of calling the function with the value.
##
## This is useful if you are building up a structure that requires more parameters
## than there are variants of `map`, `map2`, `map3` etc. for.
##
## For instance, the following two are the same:
##
## >>> const (\x, y, z -> Triple x y z)
## >>> |> map3 Parser.Str.nat Parser.Str.nat Parser.Str.nat
##
## >>> const (\x -> \y -> \z -> Triple x y z)
## >>> |> apply Parser.Str.nat
## >>> |> apply Parser.Str.nat
## >>> |> apply Parser.Str.nat
##
## (And indeed, this is how `map`, `map2`, `map3` etc. are implemented under the hood.)
##
## # Currying
## Be aware that when using `apply`, you need to explicitly 'curry' the parameters to the construction function.
## This means that instead of writing `\x, y, z -> ...`
## you'll need to write `\x -> \y -> \z -> ...`.
## This is because the parameters to the function will be applied one-by-one as parsing continues.
apply : Parser input (a -> b), Parser input a -> Parser input b
apply = \funParser, valParser ->
  combined = \input ->
    {val: funVal, input: rest} <- Result.after (runPartial funParser input)
    (runPartial valParser rest)
    |> Result.map \{val: val, input: rest2} ->
      {val: funVal val, input: rest2}
  @Parser combined

## Runs `firstParser` and (only) if it succeeds,
## runs the function `buildNextParser` on its result value.
## This function returns a new parser, which is finally run.
##
## `andThen` is usually more flexible than necessary, and less efficient
## than using `const` with `map` and/or `apply`.
## Consider using those functions first.
# TODO I am considering leaving this function out alltogether
# As using it is an anti-pattern.
andThen : Parser input a, (a -> Parser input b) -> Parser input b
andThen = \firstParser, buildNextParser ->
  fun = \input ->
    {val: firstVal, input: rest} <- Result.after (runPartial firstParser input)
    nextParser = (buildNextParser firstVal)
    runPartial nextParser rest
  @Parser fun

# NOTE: Using this implementation in an actual program,
# currently causes a compile-time StackOverflow (c.f. https://github.com/rtfeldman/roc/issues/3444 )
#  oneOfBroken : List (Parser input a) -> Parser input a
#  oneOfBroken = \parsers ->
#    List.walkBackwards parsers (fail "Always fail") (\laterParser, earlierParser -> alt earlierParser laterParser)

# And this one as well
#  oneOfBroken2 : List (Parser input a) -> Parser input a
#  oneOfBroken2 = \parsers ->
#    if List.isEmpty parsers then
#      fail "(always fail)"
#    else
#      firstParser = List.get parsers (List.len parsers - 1) |> Result.withDefault (fail "this should never happen!!")
#      alt firstParser (oneOfBroken2 (List.dropLast parsers))

## Try a bunch of different parsers.
##
## The first parser which is tried is the one at the front of the list,
## and the next one is tried until one succeeds or the end of the list was reached.
##
## >>> boolParser : Parser RawStr Bool
## >>> boolParser = oneOf [string "true", string "false"] |> map (\x -> if x == "true" then True else False)
# NOTE: This implementation works, but is limited to parsing strings.
# Blocked until issue #3444 is fixed.
oneOf : List (Parser RawStr a) -> Parser RawStr a
oneOf = \parsers ->
  @Parser \input ->
    List.walkUntil parsers (Err (ParsingFailure "(no possibilities)")) \_, parser ->
      when runPartialRaw parser input is
        Ok val ->
          Break (Ok val)
        Err problem ->
          Continue (Err problem)

## Transforms the result of parsing into something else,
## using the given transformation function.
map : Parser input a, (a -> b) -> Parser input b
map = \simpleParser, transform ->
  const transform
  |> apply simpleParser

## Transforms the result of parsing into something else,
## using the given two-parameter transformation function.
map2 : Parser input a, Parser input b, (a, b -> c) -> Parser input c
map2 = \parserA, parserB, transform ->
  const (\a -> \b -> transform a b)
  |> apply parserA
  |> apply parserB

## Transforms the result of parsing into something else,
## using the given three-parameter transformation function.
##
## If you need transformations with more inputs,
## take a look at `apply`.
map3 : Parser input a, Parser input b, Parser input c, (a, b, c-> d) -> Parser input d
map3 = \parserA, parserB, parserC, transform ->
  const (\a -> \b -> \c -> transform a b c)
  |> apply parserA
  |> apply parserB
  |> apply parserC

# ^ And this could be repeated for as high as we want, of course.

## Runs a parser lazily
##
## This is (only) useful when dealing with a recursive structure.
## For instance, consider a type `Comment : { message: String, responses: List Comment }`.
## Without `lazy`, you would ask the compiler to build an infinitely deep parser.
## (Resulting in a compiler error.)
##
lazy : ({} -> Parser input a) -> Parser input a
lazy = \thunk ->
  andThen (const {}) thunk

maybe : Parser input a -> Parser input (Result a [Nothing])
maybe = \parser ->
  alt (parser |> map (\val -> Ok val)) (const (Err Nothing))

manyImpl : Parser input a, List a, input -> Result { input : input, val : List a } [ParsingFailure Str]
manyImpl = \parser, vals, input ->
  result = runPartial parser input
  when result is
    Err _ ->
      Ok {val: vals, input: input}
    Ok {val: val, input: inputRest} ->
      manyImpl parser (List.append vals val) inputRest

## A parser which runs the element parser *zero* or more times on the input,
## returning a list containing all the parsed elements.
##
## Also see `oneOrMore`.
many : Parser input a -> Parser input (List a)
many = \parser ->
  @Parser \input ->
    manyImpl parser [] input

## A parser which runs the element parser *one* or more times on the input,
## returning a list containing all the parsed elements.
##
## Also see `many`.
oneOrMore : Parser input a -> Parser input (List a)
oneOrMore = \parser ->
  const (\val -> \vals -> List.prepend vals val)
  |> apply parser
  |> apply (many parser)
  #  moreParser : Parser (a -> (List a))
  #  moreParser =
  #      many parser
  #      |> map (\vals -> (\val -> List.prepend vals val))
  #  apply parser moreParser

  #  val <- andThen parser
  #  parser
  #  |> many
  #  |> map (\vals -> List.prepend vals val)

#  betweenBraces : Parser input a -> Parser input a
#  betweenBraces = \parser ->
#    string "["
#    |> applyOld (parser |> map (\res -> \_ -> res))
#    |> applyOld (string "]" |> map (\_ -> \res -> res))

## Runs a parser for an 'opening' delimiter, then your main parser, then the 'closing' delimiter,
## and only returns the result of your main parser.
##
## Useful to recognize structures surrounded by delimiters (like braces, parentheses, quotes, etc.)
##
## >>> betweenBraces  = \parser -> parser |> between (scalar '[') (scalar ']')
between : Parser input a, Parser input open, Parser input close -> Parser input a
between = \parser, open, close->
  const (\_ -> \val -> \_ -> val)
  |> apply open
  |> apply parser
  |> apply close

betweenBraces : Parser RawStr a -> Parser RawStr a
betweenBraces = \parser ->
  between parser (scalar '[') (scalar ']') 

sepBy1 : Parser input a, Parser input sep -> Parser input (List a)
sepBy1 = \parser, separator ->
  parserFollowedBySep =
    const (\_ -> \val -> val)
    |> apply separator
    |> apply parser
  const (\val -> \vals -> List.prepend vals val)
  |> apply parser
  |> apply (many parserFollowedBySep)

sepBy : Parser input a, Parser input sep -> Parser input (List a)
sepBy = \parser, separator ->
  alt (sepBy1 parser separator) (const [])

# Specific string-based parsers:

RawStr : List U8

strFromRaw : RawStr -> Str
strFromRaw = \rawStr ->
  rawStr
  |> Str.fromUtf8
  |> Result.withDefault "Unexpected problem while turning a List U8 (that was originally a Str) back into a Str. This should never happen!"

strToRaw : Str -> RawStr
strToRaw = \str ->
  str |> Str.toUtf8

strFromScalar : U32 -> Str
strFromScalar = \scalarVal ->
  (Str.appendScalar "" (Num.intCast scalarVal))
  |> Result.withDefault  "Unexpected problem while turning a U32 (that was probably originally a scalar constant) into a Str. This should never happen!"

strFromCodepoint : U8 -> Str
strFromCodepoint = \cp ->
  strFromRaw [cp]

## Runs a parser against the start of a list of scalars, allowing the parser to consume it only partially.
runPartialRaw : Parser RawStr a, RawStr -> Result {val: a, input: RawStr} [ParsingFailure Str]
runPartialRaw = \parser, input ->
  runPartial parser input

## Runs a parser against the start of a string, allowing the parser to consume it only partially.
##
## - If the parser succeeds, returns the resulting value as well as the leftover input.
## - If the parser fails, returns `Err (ParsingFailure msg)`
runPartialStr : Parser RawStr a, Str -> Result {val: a, input: Str} [ParsingFailure Str]
runPartialStr = \parser, input ->
  parser
  |> runPartialRaw (strToRaw input)
  |> Result.map \{val: val, input: restRaw} ->
    {val: val, input: (strFromRaw restRaw)}

## Runs a parser against a string, requiring the parser to consume it fully.
##
## - If the parser succeeds, returns `Ok val`
## - If the parser fails, returns `Err (ParsingFailure msg)`
## - If the parser succeeds but does not consume the full string, returns `Err (ParsingIncomplete leftover)`
runRaw : Parser RawStr a, RawStr -> Result a [ParsingFailure Str, ParsingIncomplete RawStr]
runRaw = \parser, input ->
  run parser input (\leftover -> List.len leftover == 0)

runStr : Parser RawStr a, Str -> Result a [ParsingFailure Str, ParsingIncomplete Str]
runStr = \parser, input ->
  parser
  |> runRaw (strToRaw input)
  |> Result.mapErr \problem ->
      when problem is
        ParsingFailure msg ->
          ParsingFailure msg
        ParsingIncomplete leftoverRaw ->
          ParsingIncomplete (strFromRaw leftoverRaw)

codepoint : U8 -> Parser RawStr U8
codepoint = \expectedCodePoint ->
  @Parser \input ->
    {before: start, others: inputRest} = List.split input 1
    if List.isEmpty start then
        errorChar = strFromCodepoint expectedCodePoint
        Err (ParsingFailure "expected char `\(errorChar)` but input was empty")
    else
      if start == (List.single expectedCodePoint) then
        Ok {val: expectedCodePoint, input: inputRest}
      else
        errorChar = strFromCodepoint expectedCodePoint
        otherChar = strFromRaw start
        inputStr = strFromRaw input
        Err (ParsingFailure "expected char `\(errorChar)` but found `\(otherChar)`.\n While reading: `\(inputStr)`")

stringRaw : List U8 -> Parser RawStr (List U8)
stringRaw = \expectedString ->
  @Parser \input ->
    {before: start, others: inputRest} = List.split input (List.len expectedString)
    if start == expectedString then
      Ok {val: expectedString, input: inputRest}
    else
      errorString = strFromRaw expectedString
      otherString = strFromRaw start
      inputString = strFromRaw input
      Err (ParsingFailure "expected string `\(errorString)` but found `\(otherString)`.\nWhile reading: \(inputString)")

string : Str -> Parser RawStr Str
string = \expectedString ->
  (strToRaw expectedString)
  |> stringRaw
  |> map (\_val -> expectedString)

scalar : U32 -> Parser RawStr U32
scalar = \expectedScalar ->
  expectedScalar
  |> strFromScalar
  |> string
  |> map (\_ -> expectedScalar)