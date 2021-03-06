module Edit.Command exposing
    (
    -- * View
      mkMenuItem
    , menuItemStyle
    , mkMenuElem

    -- * Command-line
    , cmdLineList

    -- * Keybord shortcuts
    , msgFromKeyCode
    )


import Focus as Lens
import Dict as D
import Char as Char
import Json.Decode as Decode

import Html as Html
import Html.Attributes as Atts
import Html.Events as Events

import Edit.Config as AnnoCfg
import Edit.Message.Core exposing (Msg(..))
import Edit.Command.Core exposing (..)
import Util
import Server.Core as Server


---------------------------------------------------
-- Config
---------------------------------------------------


-- -- | The global list of commands; using a list because neither `Msg` nor
-- -- `Command` is comparable...
-- globalCommands : List (Command, Msg)
-- globalCommands =
--     [ { void
--           | keyCmd = Just {keyCode=68, char='d'}
--           , lineCmd = Just "delnode"
--           , menuCmd = Just "Delete"
--           , withCtrl = Just False
--           , help = Just "Delete the selected nodes"
--       } => Delete
--     , { void
--           | keyCmd = Just {keyCode=68, char='d'}
--           , lineCmd = Just "deltree"
--           , menuCmd = Just "Delete"
--           , withCtrl = Just True
--           , help = Just "Deleted the subtrees of the selected nodes"
--       } => DeleteTree
--     , { void
--           | keyCmd = Just {keyCode=65, char='a'}
--           , menuCmd = Just "Add"
--           , help = Just "Add (a) new node(s) over the selected node(s)"
--       } => Add
--     , { void
--           | keyCmd = Just {keyCode=83, char='s'}
--           , lineCmd = Just "save"
--           , menuCmd = Just "Save"
--           , withCtrl=Just True
--       } => SaveFile
--     , { void
--           | lineCmd = Just "restart"
--           , menuCmd = Just "Restart"
--           , withCtrl = Just False
--           , help = Just "Restart annotation of the file"
--       } => ParseRaw False
--     , { void
--           | lineCmd = Just "restartpreproc"
--           , menuCmd = Just "Restart"
--           , withCtrl = Just True
--           , help = Just "Restart annotation of the file and perform preprocessing"
--       } => ParseRaw True
--     , { void
--           | keyCmd = Just {keyCode=80, char='p'}
--           , lineCmd = Just "parse"
--           , menuCmd = Just "Parse"
--           , withCtrl=Just False
--           , help = Just "Reparse the sentence"
--       } => ParseSent Server.Stanford
--     , { void
--           | keyCmd = Just {keyCode=80, char='p'}
--           , lineCmd = Just "parsepos"
--           , menuCmd = Just "Parse"
--           , help = Just "Reparse the selected sub-sentence(s) without changing the POS tags"
--           , withCtrl=Just True
--       } => ParseSentPos Server.Stanford
-- --     , { void
-- --           | keyCmd = Just {keyCode=80, char='p'}
-- --           , lineCmd = Just "parsetmp"
-- --           , help = Just "Reparse the selected sub-sentence(s) without changing the POS tags"
-- --       } => ParseSentPosPrim Server.Stanford
--     , { void
--           | lineCmd = Just "dopparse"
--       } => ParseSent Server.DiscoDOP
--     , { void
--           | lineCmd = Just "parsecons"
--       } => ParseSentCons Server.DiscoDOP
--     , { void
--           | lineCmd = Just "deepen" } => ApplyRules
--     , { void
--           | lineCmd = Just "splitsent"
--           , menuCmd = Just "Split sentence"
--           , help = Just "Split the current sentence into several sentences at the selected terminal nodes"
--       } => SplitTree
--     , { void
--           | lineCmd = Just "splitword"
--           , menuCmd = Just "Split word"
--           , help = Just "Split in two the token corresponding to the selected terminal"
--       } => SplitBegin
--     , { void
--           | lineCmd = Just "connect" } => Connect
--     , { void
--           | lineCmd = Just "compare" } => Compare
--     , { void
--           | lineCmd = Just "join" } => Join
--     , { void
--           | lineCmd = Just "joinwords"
--           , menuCmd = Just "Join words"
--           , help = Just "Concatenate the tokens corresponding to the selected terminals"
--       } => ConcatWords
--     , { void
--           | lineCmd = Just "dummify"
--           , menuCmd = Just "Dummify"
--           , help = Just "Destroy the entire tree"
--       } => Dummy
--
--     -- Temporal section
--     , { void
--           | keyCmd = Just {keyCode=83, char='s'}
--           , menuCmd = Just "Signal"
--           , help = Just "Mark the selected node as signal"
--       } => MkEntity "Signal"
--     , { void
--           | keyCmd = Just {keyCode=84, char='t'}
--           , menuCmd = Just "Timex"
--           , help = Just "Mark the selected node as timex"
--       } => MkEntity "Timex"
--     , { void
--           | keyCmd = Just {keyCode=86, char='v'}
--           , menuCmd = Just "Event"
--           , help = Just "Mark the selected node as event"
--       } => MkEntity "Event"
--     ]


---------------------------------------------------
-- Keyboard shortcut-related utilities
---------------------------------------------------


-- | What is the message for the given key?
msgFromKeyCode
    :  AnnoCfg.Config
    -> Bool -- ^ Is CTLR down?
    -> Int -- ^ The code
    -> Maybe Msg
msgFromKeyCode cfg isCtrl code =
    let
        -- the character corresponding to the code
        char = Char.toLower <| Char.fromCode code
        -- NOTE: we assume that at most one relevant element should be retrieved
        isRelevant cmd =
            case cmd.keyCmd of
                Nothing -> False
                Just key ->
                    -- key.keyCode == code &&
                    key.char == char &&
                        (
                         cmd.withCtrl == Nothing ||
                         cmd.withCtrl == Just isCtrl
                        )
        relevant =
            List.filter
                (isRelevant << Tuple.first)
                cfg.commands
                -- globalCommands
    in
        case relevant  of
            (cmd, msg) :: _ -> Just msg
            _ -> Nothing


---------------------------------------------------
-- Command-line-related utilities
---------------------------------------------------


-- | The list of command-line commands and the corresponding messages.
cmdLineList
    :  AnnoCfg.Config
    -> List (String, Msg)
cmdLineList cfg =
    let
        process (cmd, msg) =
            case cmd.lineCmd of
                Nothing -> Nothing
                Just ln -> Just (ln, msg)
    in
        Util.catMaybes
            << List.map process
            <| cfg.commands -- globalCommands


---------------------------------------------------
-- View-related utilities
---------------------------------------------------


-- | Create a menu element for a given `Msg`.
mkMenuElem
    : AnnoCfg.Config
      -- ^ Is CTRL pressed?
    -> Bool
      -- ^ Is CTRL pressed?
    -> Msg
      -- ^ The message
    -> Maybe (Html.Html Msg)
      -- ^ Doesn't succeed if there is no menu command for the given message
mkMenuElem cfg isCtrl menuMsg =
    let
        -- NOTE: we assume that at most one relevant element should be retrieved
        isRelevant (cmd, msg) =
            msg == menuMsg &&
            (cmd.withCtrl == Nothing || cmd.withCtrl == Just isCtrl)
        relevant = List.filter isRelevant cfg.commands -- globalCommands
    in
        case relevant  of
            [(cmd, msg)] -> Maybe.map (mkMenuItem msg cmd.help) <|
                case cmd.menuCmd of
                    Nothing -> Nothing
                    Just rawName -> Just <|
                        let
                            ctrlFlag = cmd.withCtrl == Just True
                        in
                            case cmd.keyCmd of
                                Nothing -> plainText ctrlFlag rawName
                                Just key ->
                                    let charStr = String.fromChar key.char in
                                    case String.indexes charStr (String.toLower rawName) of
                                        i :: _ -> emphasizeCtrl ctrlFlag i rawName
                                        _ -> plainText ctrlFlag rawName
            _ -> Nothing


-- | Create a menu item for given attributes.
mkMenuItem
    : Msg
       -- ^ The message
    -> Maybe String
       -- ^ Hint
    -> Html.Html Msg
       -- ^ Menu name (in HTML)
    -> Html.Html Msg
mkMenuItem msg hint name =
  let
    -- A version of `Events.onClick` which blocks propagation
    onClick =
        Events.onWithOptions
            "mousedown"
            (let default = Events.defaultOptions
             in {default | stopPropagation=True, preventDefault=True})
            (Decode.succeed msg)
  in
    Html.div
        ( [ onClick
          , Atts.style menuItemStyle
          ] ++ case hint of
                   Nothing -> []
                   Just x  -> [Atts.title x]
        )
    [ name ]


menuItemStyle : List (String, String)
menuItemStyle =
    [ "cursor" => "pointer"
    , "margin-left" => px 10
    , "margin-right" => px 10
    -- | To make the list of commands wrap
    , "display" => "inline-block"
    ]


---------------------------------------------------
-- Utils
---------------------------------------------------


(=>) : a -> b -> (a, b)
(=>) = (,)


px : Int -> String
px number =
  toString number ++ "px"


---------------------------------------------------
-- Showing text (NOTE: copy in the `View` module)
---------------------------------------------------


-- | The input flag tells if this is an CTRL-only command.
plainText : Bool -> String -> Html.Html Msg
plainText flag x =
    if flag
    then Html.i [] [Html.text x]
    else Html.text x


emphasize : Int -> String -> Html.Html Msg
emphasize i x =
    Html.span []
        [ Html.text (String.slice 0 i x)
        , Html.u [] [Html.text (String.slice i (i+1) x)]
        , Html.text (String.slice (i+1) (String.length x) x)
        ]


-- | The input flag tells if this is an CTRL-only command.
emphasizeCtrl : Bool -> Int -> String -> Html.Html Msg
emphasizeCtrl flag i x =
    let
        mkRoot = if flag then Html.i else Html.span
        style = [Atts.style ["text-decoration" => "underline"]]
--             if flag
--             then [Atts.style ["text-decoration" => "overline"]]
--             else [Atts.style ["text-decoration" => "underline"]]
    in
        mkRoot []
            [ Html.text (String.slice 0 i x)
            , Html.span style [Html.text (String.slice i (i+1) x)]
            , Html.text (String.slice (i+1) (String.length x) x)
            ]
