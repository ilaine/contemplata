-- | Annotation-related types.


module Edit.Anno.Core exposing
  (
  -- * Annotations
    Entity
  , Attr (..)

  -- * JSON
  , encodeEntity
  , entityDecoder
  , encodeAddr
  , addrDecoder

  -- * Lenses
  , entityType
  , entityAttr
  )


import Json.Decode as Decode
import Json.Encode as Encode

-- import Focus exposing ((=>))
import Focus as Lens

import List as L
import Dict as D

import Util
import Edit.Core exposing (Addr)


---------------------------------------------------
-- Annotations
---------------------------------------------------


-- | A generic annotation entity (e.g. Event, Timex, ...).
type alias Entity =
  { name : String
  , typ : String
  , attributes : D.Dict String Attr
    -- ^ The value of optional attributes does not have to be specified in the
    -- map above.
  }


-- | Corresponding to `Odil.Config.Attr`.
type Attr
  = Attr String -- ^ A closed or free attribute.
  | Anchor Addr


----------------------------
-- Lenses
----------------------------


-- | A lens for the type of the entity.
entityType : Lens.Focus Entity String
entityType =
  let
    get ent = ent.typ
    update f ent = {ent | typ = f ent.typ}
  in
    Lens.create get update


-- | A lens for the given attribute.
entityAttr
    : String
      -- ^ The name of the attribute
    -> Lens.Focus Entity (Maybe Attr)
entityAttr attrName =
  let
    get ent =
        D.get attrName ent.attributes
    update f ent =
        {ent | attributes = D.update attrName f ent.attributes}
  in
    Lens.create get update


-- | A lens for the given attribute.
entityAnchor
    : String
      -- ^ The name of the attribute
    -> Lens.Focus Entity (Maybe Attr)
entityAnchor attrName =
  let
    get ent =
        D.get attrName ent.attributes
    update f ent =
        {ent | attributes = D.update attrName f ent.attributes}
  in
    Lens.create get update


---------------------------------------------------
-- JSON: Decoding
---------------------------------------------------


entityDecoder : Decode.Decoder Entity
entityDecoder =
  let mkEntity name typ atts =
        { name = name
        , typ = typ
        , attributes = atts
        }
  in  Decode.map3 mkEntity
        (Decode.field "name" Decode.string)
        (Decode.field "typ" Decode.string)
        (Decode.field "attributes" attrMapDecoder)


attrMapDecoder : Decode.Decoder (D.Dict String Attr)
attrMapDecoder = Decode.dict attrDecoder


attrDecoder : Decode.Decoder Attr
attrDecoder = Decode.oneOf [pureAttrDecoder, anchorDecoder]


pureAttrDecoder : Decode.Decoder Attr
pureAttrDecoder =
  Decode.map2 (\_ val -> Attr val)
    (Decode.field "tag" (isString "Attr"))
    (Decode.field "contents" Decode.string)


anchorDecoder : Decode.Decoder Attr
anchorDecoder =
  Decode.map2 (\_ val -> Anchor val)
    (Decode.field "tag" (isString "Anchor"))
    (Decode.field "contents" addrDecoder)


isString : String -> Decode.Decoder ()
isString str0
    =  Decode.string
    |> Decode.andThen
       (\str ->
            if str == str0
            then Decode.succeed ()
            else Decode.fail <| "The two strings differ: " ++ str0 ++ " /= " ++ str
       )


addrDecoder : Decode.Decoder Addr
addrDecoder =
  Decode.map2 (\treeId nodeId -> (treeId, nodeId))
    -- (Decode.index 0 Decode.string)
    (Decode.index 0 Decode.int)
    (Decode.index 1 Decode.int)


---------------------------------------------------
-- JSON: Encoding
---------------------------------------------------


encodeEntity : Entity -> Encode.Value
encodeEntity r =
  Encode.object
    [ ("tag", Encode.string "Entity")
    , ("name", Encode.string r.name)
    , ("typ", Encode.string r.typ)
    , ("attributes", encodeAttrMap r.attributes)
    ]


encodeAttrMap : D.Dict String Attr -> Encode.Value
encodeAttrMap =
  let encodePair (key, val) = (key, encodeAttr val)
  in  Encode.object << L.map encodePair << D.toList


encodeAttr : Attr -> Encode.Value
encodeAttr attr =
  case attr of
    Attr x -> Encode.object
      [ ("tag", Encode.string "Attr")
      , ("contents", Encode.string x)
      ]
    Anchor x -> Encode.object
      [ ("tag", Encode.string "Anchor")
      , ("contents", encodeAddr x)
      ]


encodeAddr : Addr -> Encode.Value
encodeAddr (x, y) = Encode.list [Encode.int x, Encode.int y]


---------------------------------------------------
-- Annotation modifications
---------------------------------------------------


-- -- | To signal a change of the attribute type.
-- type alias EntityType =
--     { name : String
--     , typ : String
--     }
--
--
-- -- | To signal a change of the attribute value.
-- type alias EntityAttr =
--     { name : String
--     , attr : Maybe Attr
--       -- ^ `Nothing` when the value should be deleted from the attributes map.
--       -- TODO: should we make sure we don't delete a required attribute?
--       -- In general, we should somehow make sure that the change is consistent
--       -- with the config.
--     }
