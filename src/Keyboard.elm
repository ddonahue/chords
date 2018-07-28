module Keyboard exposing (Keyboard, init, Msg(..), update, view)

import Chord exposing (Chord)
import Colour
import CustomEvents exposing (onLeftDown, onKeyDown, onIntInput)
import Path
import Player exposing (Player)

import Html exposing (Html, span, input)
import Html.Attributes as Attributes exposing (attribute, style)
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA

type alias Keyboard =
  { player : Player
  , customChord : Maybe Chord
  , customOctave : Int
  , showCustomChord : Bool
  }

init : Keyboard
init =
  { player = Player.init
  , customChord = Nothing
  , customOctave = 0
  , showCustomChord = False
  }

type Msg
  = ShowCustomChord Bool
  | SetOctave Int
  | AddPitch (Int, Int)
  | RemovePitch (Int, Int)

update : Msg -> Keyboard -> Keyboard
update msg keyboard =
  case msg of
    ShowCustomChord showCustomChord ->
      { keyboard
      | player = Player.init
      , showCustomChord = showCustomChord
      }

    SetOctave octave ->
      { player = Player.init
      , customChord =
          case Player.lastPlayed keyboard.player of
            Nothing ->
              keyboard.customChord
            Just idChord ->
              Just idChord.chord
      , customOctave = octave
      , showCustomChord = True
      }

    AddPitch ( lowestPitch, pitch ) ->
      let
        pitchSet =
          if keyboard.showCustomChord then
            Chord.toPitchSet
              lowestPitch
              keyboard.customOctave
              keyboard.customChord
          else
            Chord.toPitchSet
              lowestPitch
              0
              ( Maybe.map
                  .chord
                  (Player.lastPlayed keyboard.player)
              )
      in let
        newPitchSet =
          Set.filter
            ( inRange
                (pitch - maxChordRange)
                (pitch + maxChordRange)
            )
            (Set.insert pitch pitchSet)
      in let
        ( newChord, newOctave ) =
          case Chord.fromPitchSet lowestPitch newPitchSet of
            Just x ->
              x
            Nothing ->
              Debug.crash
                "Keyboard.update: Pitch set empty after inserting pitch"
      in
        { player = Player.init
        , customChord = Just newChord
        , customOctave = newOctave
        , showCustomChord = True
        }

    RemovePitch ( lowestPitch, pitch ) ->
      let
        pitchSet =
          if keyboard.showCustomChord then
            Chord.toPitchSet
              lowestPitch
              keyboard.customOctave
              keyboard.customChord
          else
            Chord.toPitchSet
              lowestPitch
              0
              ( Maybe.map
                  .chord
                  (Player.lastPlayed keyboard.player)
              )
      in let
        newPitchSet =
          Set.remove pitch pitchSet
      in
        case Chord.fromPitchSet lowestPitch newPitchSet of
          Just ( newChord, newOctave ) ->
            { player = Player.init
            , customChord = Just newChord
            , customOctave = newOctave
            , showCustomChord = True
            }
          Nothing ->
            { player = Player.init
            , customChord = Nothing
            , customOctave = 0
            , showCustomChord = False
            }

maxChordRange : Int
maxChordRange = 23

inRange : Int -> Int -> Int -> Bool
inRange low high x =
  low <= x && x <= high

view : String -> Int -> Int -> Keyboard -> Html Msg
view gridArea tonic lowestPitch keyboard =
  let
    maybeChord =
      if keyboard.showCustomChord then
        keyboard.customChord
      else
        ( Maybe.map
            .chord
            (Player.lastPlayed keyboard.player)
        )
    octave =
      if keyboard.showCustomChord then
        keyboard.customOctave
      else
        0
    maxOctave =
      case maybeChord of
        Nothing ->
          0
        Just chord ->
          let
            rootPitch =
              (chord.root - lowestPitch) % 12 + lowestPitch
            highestOffset =
              case List.reverse chord.flavor of
                [] ->
                  0
                flavorPitch :: _ ->
                  flavorPitch
          in let
            highestPitch = rootPitch + highestOffset
            maxPitch = lowestPitch + 11 + maxChordRange
          in let
            maxTransposition = maxPitch - highestPitch
          in
            (maxTransposition - maxTransposition % 12) // 12
  in let
    pitchSet =
      Chord.toPitchSet lowestPitch octave maybeChord
  in
    span
      [ style
          [ ( "grid-area", gridArea )
          ]
      ]
      [ span
          [ style
              [ ( "display", "block" )
              ]
          ]
          [ input
              [ Attributes.type_ "number"
              , onIntInput octave SetOctave
              , Attributes.value (toString octave)
              , Attributes.min "0"
              , Attributes.max (toString maxOctave)
              ]
              []
          ]
      , viewKeys
          tonic
          lowestPitch
          (lowestPitch + 11 + maxChordRange)
          pitchSet
      ]

-- the origin is the top left corner of middle C,
-- not including its border
viewKeys : Int -> Int -> Int -> Set Int -> Html Msg
viewKeys tonic lowestPitch highestPitch pitchSet =
  let
    left = viewBoxLeft lowestPitch
  in let
    right = viewBoxRight highestPitch
  in let
    width = right - left
  in let
    height = fullHeight + borderWidth
  in
    Svg.svg
      [ SA.width (toString width)
      , SA.height (toString height)
      , SA.viewBox
          ( String.join
              " "
              [ toString left
              , toString -borderWidth
              , toString width
              , toString height
              ]
          )
      ]
      ( List.concat
          [ [ Svg.defs
                []
                [ blackKeyGradient
                , whiteKeyGradient
                , specularGradient
                ]
            , Svg.rect
                [ SA.x (toString left)
                , SA.y (toString -borderWidth)
                , SA.width (toString width)
                , SA.height (toString height)
                , SA.fill "black"
                ]
                []
            ]
          , List.concatMap
              (viewKey tonic lowestPitch highestPitch pitchSet)
              (List.range lowestPitch highestPitch)
          , [ Svg.text_
                [ style
                    [ ( "pointer-events", "none" )
                    ]
                , SA.textAnchor "middle"
                , SA.x
                    (toString (0.5 * (headWidth - borderWidth)))
                , SA.y
                    ( toString
                        ( fullHeight - borderWidth -
                            0.25 * (headWidth - borderWidth)
                        )
                    )
                ]
                [ Svg.text "C4"
                ]
            ]
          ]
      )

viewBoxLeft : Int -> Float
viewBoxLeft lowestPitch =
  if isWhiteKey lowestPitch then
    headLeft lowestPitch - borderWidth
  else
    neckLeft lowestPitch - borderWidth

viewBoxRight : Int -> Float
viewBoxRight highestPitch =
  if isWhiteKey highestPitch then
    headLeft highestPitch + headWidth
  else
    neckLeft (highestPitch + 1)

viewKey : Int -> Int -> Int -> Set Int -> Int -> List (Svg Msg)
viewKey tonic lowestPitch highestPitch pitchSet pitch =
  let
    selected = Set.member pitch pitchSet
  in let
    action =
      if selected then
        RemovePitch ( lowestPitch, pitch )
      else
        AddPitch ( lowestPitch, pitch )
  in
    if isWhiteKey pitch then
      let
        path = whitePath lowestPitch highestPitch pitch
      in
        [ Svg.path
            [ style
                [ ( "cursor", "pointer" )
                ]
            , onLeftDown action
            , onKeyDown
                [ ( 13, action )
                , ( 32, action )
                ]
            , attribute "tabindex" "0"
            , SA.fill
                ( if selected then
                    Colour.pitchBg tonic pitch
                  else
                    "white"
                )
            , SA.d path
            ]
            []
        ] ++
          ( if selected then
              [ Svg.path
                  [ style
                      [ ( "pointer-events", "none" )
                      ]
                  , SA.fill "url(#whiteKeyGradient)"
                  , SA.d path
                  ]
                  []
              ]
            else
              []
          )
    else
      [ Svg.rect
          [ style
              [ ( "cursor", "pointer" )
              ]
          , onLeftDown action
          , onKeyDown
              [ ( 13, action )
              , ( 32, action )
              ]
          , SA.fill
              ( if Set.member pitch pitchSet then
                  Colour.pitchBg tonic pitch
                else
                  ""
              )
          , SA.strokeWidth (toString borderWidth)
          , SA.strokeLinejoin "round"
          , SA.x (toString (neckLeft pitch))
          , SA.y "0"
          , SA.width (toString blackWidth)
          , SA.height (toString (blackHeight - borderWidth))
          ]
          []
      , Svg.path
          [ style
              [ ( "pointer-events", "none" )
              ]
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (toString (leftSideOpacity selected))
          , SA.d (leftSidePath pitch)
          ]
          []
      , Svg.path
          [ style
              [ ( "pointer-events", "none" )
              ]
          , SA.fill "url(#specularGradient)"
          , SA.opacity (toString (specularOpacity selected))
          , SA.d (specularPath pitch)
          ]
          []
      , Svg.path
          [ style
              [ ( "pointer-events", "none" )
              ]
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (toString fingerOpacity)
          , SA.d (fingerPath pitch)
          ]
          []
      , Svg.path
          [ style
              [ ( "pointer-events", "none" )
              ]
          , SA.fill "url(#blackKeyGradient)"
          , SA.opacity (toString (hillOpacity selected))
          , SA.d (hillPath pitch)
          ]
          []
      ]

isWhiteKey : Int -> Bool
isWhiteKey pitch =
  (pitch % 2 == 1) == (pitch % 12 > 4)

whitePath : Int -> Int -> Int -> String
whitePath lowestPitch highestPitch pitch =
  String.join
    " "
    [ Path.bigM
        ( if pitch == lowestPitch then
            headLeft pitch
          else
            neckLeft pitch
        )
        0
    , Path.bigV blackHeight
    , Path.bigH (headLeft pitch)
    , Path.bigV (fullHeight - borderWidth - borderRadius)
    , Path.a
        borderRadius borderRadius
        90 False False
        borderRadius borderRadius
    , Path.h (headWidth - borderWidth - 2 * borderRadius)
    , Path.a
        borderRadius borderRadius
        90 False False
        borderRadius -borderRadius
    , Path.bigV blackHeight
    , Path.bigH
        ( if pitch == highestPitch then
            headLeft pitch + headWidth - borderWidth
          else
            neckLeft (pitch + 1) - borderWidth
        )
    , Path.bigV 0
    , Path.bigZ
    ]

fingerPath : Int -> String
fingerPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch + sideWidth) 0
    , Path.bigV
        (blackHeight - borderWidth - hillHeight - nailHeight)
    , Path.c
        0 (nailHeight / 0.75)
        (blackWidth - 2 * sideWidth) (nailHeight / 0.75)
        (blackWidth - 2 * sideWidth) 0
    , Path.bigV 0
    , Path.bigZ
    ]

leftSidePath : Int -> String
leftSidePath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch) 0
    , Path.bigV (blackHeight - borderWidth)
    , Path.c
        (hillHeight / 1.5 / hillSlope) (-hillHeight / 1.5)
        (0.25 * blackWidth + hillHeight / 3 / hillSlope) (-hillHeight)
        (0.5 * blackWidth) (-hillHeight)
    , Path.c
        (-0.25 * blackWidth + 0.5 * sideWidth) 0
        (-0.5 * blackWidth + sideWidth) (-nailHeight / 3)
        (-0.5 * blackWidth + sideWidth) (-nailHeight)
    , Path.bigV 0
    , Path.bigZ
    ]

specularPath : Int -> String
specularPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch) (blackHeight - borderWidth - specularHeight)
    , Path.bigV (blackHeight - borderWidth)
    , Path.c
        (hillHeight / 1.5 / hillSlope) (-hillHeight / 1.5)
        (0.25 * blackWidth + hillHeight / 3 / hillSlope) (-hillHeight)
        (0.5 * blackWidth) (-hillHeight)
    , Path.c
        (-0.25 * blackWidth + 0.5 * sideWidth) 0
        (-0.5 * blackWidth + sideWidth) (-nailHeight / 3)
        (-0.5 * blackWidth + sideWidth) (-nailHeight)
    , Path.bigV (blackHeight - borderWidth - specularHeight)
    , Path.bigZ
    ]

hillPath : Int -> String
hillPath pitch =
  String.join
    " "
    [ Path.bigM (neckLeft pitch + blackWidth) 0
    , Path.bigV (blackHeight - borderWidth)
    , Path.h -blackWidth
    , Path.partialC
        rightShineT
        (hillHeight / 0.75 / hillSlope) (-hillHeight / 0.75)
        (blackWidth - hillHeight / 0.75 / hillSlope) (-hillHeight / 0.75)
        blackWidth 0
    , Path.bigV 0
    , Path.bigZ
    ]

neckLeft : Int -> Float
neckLeft pitch =
  let
    pitchClass = pitch % 12
  in let
    octave = (pitch - pitchClass) // 12 - 5
  in let
    classLeft =
      if pitchClass > 4 then
        toFloat (1 + 4 * pitchClass) * headWidth / 7
      else
        toFloat (pitchClass % 2 + 25 * pitchClass) * headWidth / 42
  in
    classLeft + 7 * headWidth * toFloat octave

headLeft : Int -> Float
headLeft pitch =
  let
    pitchClass = pitch % 12
  in let
    octave = (pitch - pitchClass) // 12 - 5
  in let
    letterIndex = (pitchClass * 7 + 6) // 12
  in
    headWidth * toFloat (letterIndex + 7 * octave)

borderWidth : Float
borderWidth = 0.5 * scale

-- white keys have rounded corners at the bottom
-- the radius is measured at the edge of the white area, inside the border
borderRadius : Float
borderRadius = 0.75 * scale

-- all widths and heights include one border width
headWidth : Float
headWidth = 7 * scale

blackHeight : Float
blackHeight = 20 * scale

fullHeight : Float
fullHeight = 31 * scale

scale : Float
scale = 6

-- black key lighting parameters (these don't include any border width)
blackWidth : Float
blackWidth = 4 * headWidth / 7 - borderWidth

nailHeight : Float
nailHeight = 0.27 * blackWidth

hillHeight : Float
hillHeight = 0.44 * blackWidth

hillSlope : Float
hillSlope = 7

sideWidth : Float
sideWidth = 0.07 * blackWidth

rightShineT : Float
rightShineT = 1 - 0.12

specularHeight : Float
specularHeight = 2 * blackWidth

fingerOpacity : Float
fingerOpacity = 0.28

hillOpacity : Bool -> Float
hillOpacity selected =
  if selected then 0.6 else 0.46

leftSideOpacity : Bool -> Float
leftSideOpacity selected =
  if selected then 1 else 0.67

specularOpacity : Bool -> Float
specularOpacity selected =
  if selected then 1 else 0.4

blackKeyStartOpacity : Float
blackKeyStartOpacity = 0.3

blackKeyGradient : Svg msg
blackKeyGradient =
  Svg.linearGradient
    [ SA.id "blackKeyGradient"
    , SA.y1 "0%"
    , SA.y2 "100%"
    , SA.x1 "50%"
    , SA.x2 "50%"
    ]
    [ Svg.stop
        [ SA.offset "0%"
        , style
            [ ( "stop-color", "white" )
            , ( "stop-opacity", toString blackKeyStartOpacity )
            ]
        ]
        []
    , Svg.stop
        [ SA.offset "100%"
        , style
            [ ( "stop-color", "white" )
            , ( "stop-opacity", "1" )
            ]
        ]
        []
    ]

whiteKeyGradient : Svg msg
whiteKeyGradient =
  let
    startOpacity = blackKeyStartOpacity * fingerOpacity
    slope =
      (1 - blackKeyStartOpacity) * fingerOpacity /
        (blackHeight - borderWidth - hillHeight)
  in let
    endOpacity =
      startOpacity + slope * (fullHeight - borderWidth)
  in
    Svg.linearGradient
      [ SA.id "whiteKeyGradient"
      , SA.y1 "0%"
      , SA.y2 "100%"
      , SA.x1 "50%"
      , SA.x2 "50%"
      ]
      [ Svg.stop
          [ SA.offset "0%"
          , style
              [ ( "stop-color", "white" )
              , ( "stop-opacity", toString startOpacity )
              ]
          ]
          []
      , Svg.stop
          [ SA.offset "100%"
          , style
              [ ( "stop-color", "white" )
              , ( "stop-opacity", toString endOpacity )
              ]
          ]
          []
      ]

specularGradient : Svg msg
specularGradient =
  Svg.radialGradient
    [ SA.id "specularGradient"
    , SA.cx "7.1%"
    , SA.cy "76%"
    , SA.r "7%"
    , SA.fx "7.1%"
    , SA.fy "76%"
    , SA.gradientTransform "scale(4 1)"
    ]
    [ Svg.stop
        [ SA.offset "0%"
        , style
            [ ( "stop-color", "white" )
            , ( "stop-opacity", "1" )
            ]
        ]
        []
    , Svg.stop
        [ SA.offset "100%"
        , style
            [ ( "stop-color", "white" )
            , ( "stop-opacity", "0" )
            ]
        ]
        []
    ]
