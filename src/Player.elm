module Player exposing
  ( Player, setTime, willChange, PlayStatus, playStatus, stopPlaying
  , playPad, playStrum, playArpeggio
  )

import Arp
import AudioChange exposing (AudioChange(..))
import IdChord exposing (IdChord)
import Note

type alias Player =
  { openings : List Opening
  , schedule : List Segment
  }

type alias Opening =
  { endTime : Float
  , beatInterval : Float
  , beat : Float
  , id : Int
  , highStart : Bool
  }

type alias Segment =
  { id : Int
  , stop : Float
  }

-- bool is true when chord sequence finishes
setTime : Float -> Player -> Maybe ( Player, Bool )
setTime now player =
  case player.schedule of
    [] ->
      if shouldDeleteOpenings now player.openings then
        Just ( { player | openings = [] }, True )
      else
        Nothing
    segment :: rest ->
      if now < segment.stop then
        Nothing
      else
        case dropSegmentsBefore now rest of
          [] ->
            if shouldDeleteOpenings now player.openings then
              Just ( { openings = [], schedule = [] }, True )
            else
              Just ( { player | schedule = [] }, player.openings == [] )
          newSchedule ->
            Just ( { player | schedule = newSchedule }, False )

shouldDeleteOpenings : Float -> List Opening -> Bool
shouldDeleteOpenings now openings =
  case openings of
    [] -> False
    opening :: _ -> now > opening.endTime

dropSegmentsBefore : Float -> List Segment -> List Segment
dropSegmentsBefore now segments =
  case segments of
    [] -> []
    segment :: rest ->
      if now < segment.stop then segments
      else dropSegmentsBefore now rest

willChange : Player -> Bool
willChange player =
  case player.schedule of
    [] -> player.openings /= []
    segment :: _ -> segment.stop < infinity

type alias PlayStatus =
  { active : Int
  , next : Int
  , stoppable : Bool
  }

playStatus : Player -> PlayStatus
playStatus player =
  case player.schedule of
    [] ->
      { active = -1, next = -1, stoppable = False }
    [ segment ] ->
      { active = segment.id
      , next = -1
      , stoppable = segment.stop == infinity
      }
    segment :: nextSegment :: _ ->
      { active = segment.id
      , next = nextSegment.id
      , stoppable = segment.stop == infinity
      }

stopPlaying : Float -> Player -> ( Player, List AudioChange )
stopPlaying now player =
  ( { openings = [], schedule = [] }
  , [ MuteAllNotes { t = now, before = False } ]
  )

playPad : Int -> IdChord -> Float -> Player -> ( Player, List AudioChange )
playPad lowestNote { id, chord } now player =
  ( { player
    | openings = []
    , schedule = [ { id = id, stop = infinity } ]
    }
  , List.concat
      [ stopOldChord now id now player.schedule
      , [ SetAttack 0.2
        , SetPeak 0.25
        , SetDecay infinity
        ]
      , List.map
          (AddNote << Note.mapTime (always now))
          (Arp.strum lowestNote chord)
      ]
  )

playStrum :
  Float -> Int -> IdChord -> Float -> Player -> ( Player, List AudioChange )
playStrum strumInterval lowestNote { id, chord } now player =
  ( { player
    | openings = []
    , schedule = [ { id = id, stop = now + 2.25 } ]
    }
  , List.concat
      [ stopOldChord now id now player.schedule
      , [ SetAttack 0
        , SetPeak 0.5
        , SetDecay 3
        ]
      , List.map
          ( AddNote <<
              Note.mapTime ((+) now << (*) strumInterval)
          )
          (Arp.strum lowestNote chord)
      ]
  )

playArpeggio :
  Float -> Int -> IdChord -> Float -> Player -> ( Player, List AudioChange )
playArpeggio beatInterval lowestNote { id, chord } now player =
  let
    truncatedOpenings = dropOpeningsAfter now player.openings
  in let
    ( startTime, beat, highStart ) =
      case truncatedOpenings of
        [] ->
          ( now, now / beatInterval, False )
        opening :: _ ->
          ( opening.beat * opening.beatInterval
          , if opening.beatInterval == beatInterval then
              opening.beat
            else
              opening.beat * opening.beatInterval / beatInterval
          , opening.highStart && opening.id /= id
          )
  in let
    additionalOpenings =
      [ { endTime = (beat + 4 + leniency) * beatInterval
        , beatInterval = beatInterval
        , beat = beat + 4
        , id = id
        , highStart = False
        }
      , { endTime = (beat + 2 + leniency) * beatInterval
        , beatInterval = beatInterval
        , beat = beat + 2
        , id = id
        , highStart = True
        }
      ]
  in let
    truncatedSchedule =
      if now < startTime then
        case player.schedule of
          [] ->
            []
          segment :: _ ->
            [ { id = segment.id
              , stop = startTime
              }
            ]
      else
        []
  in let
    additionalSchedule =
      [ { id = id
        , stop = (beat + 4) * beatInterval
        }
      ]
  in
    ( { player
      | openings = additionalOpenings ++ truncatedOpenings
      , schedule = truncatedSchedule ++ additionalSchedule
      }
    , List.concat
        [ stopOldChord startTime id now player.schedule
        , [ SetAttack 0
          , SetPeak 0.5
          , SetDecay 1.5
          ]
        , List.map
            ( AddNote <<
                Note.mapTime
                  (max now << (+) startTime << (*) beatInterval)
            )
            ( if highStart then
                Arp.continuation lowestNote chord
              else
                Arp.intro lowestNote chord
            )
        ]
    )

dropOpeningsAfter : Float -> List Opening -> List Opening
dropOpeningsAfter t openings =
  case openings of
    [] -> openings
    _ :: previousOpenings ->
      case previousOpenings of
        [] -> openings
        previousOpening :: _ ->
          if previousOpening.endTime < t then openings
          else dropOpeningsAfter t previousOpenings

leniency : Float
leniency = 0.05

stopOldChord : Float -> Int -> Float -> List Segment -> List AudioChange
stopOldChord startTime id now schedule =
  let
    changeTime =
      { t = max now startTime
      , before = now < startTime
      }
  in
    case schedule of
      [] ->
        [ CancelFutureNotes changeTime ]
      segment :: _ ->
        if segment.stop == infinity then
          [ SetDecay 0.5, CancelFutureNotes changeTime ]
        else if segment.id /= id then
          [ MuteAllNotes changeTime ]
        else
          [ CancelFutureNotes changeTime ]

infinity : Float
infinity = 1/0
