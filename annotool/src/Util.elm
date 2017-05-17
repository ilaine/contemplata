module Util exposing
  ( split, catMaybes, find, unless, mappend, guard, and, average)


import List as L


-- | The results is (ls, rs) where `ls` are all the left-most elements which do
-- | not satisfy the given predicate, while `rs` is the rest. In particular, the
-- | first element of `rs` satisfies the predicate.
split : (a -> Bool) -> List a -> (List a, List a)
split p xs =
  let
    ys = case xs of
      [] -> ([], [])
      hd :: tl ->
        if p hd
          then ([], xs)
          else
            let (ls, rs) = split p tl
            in  (hd :: ls, rs)
     -- revFst (x, y) = (List.reverse x, y)
  in
    -- revFst ys
    ys


catMaybes : List (Maybe a) -> List a
catMaybes xs =
  case xs of
    [] -> []
    hd :: tl ->
      case hd of
        Nothing -> catMaybes tl
        Just x  -> x :: catMaybes tl


-- | Find the first element which satisfies a given predicate.
find : (a -> Bool) -> List a -> Maybe a
find p xs =
  case xs of
    [] -> Nothing
    hd :: tl ->
      case p hd of
        True  -> Just hd
        False -> find p tl


unless : Bool -> a -> Maybe a
unless flag x = case flag of
  True -> Nothing
  False -> Just x


mappend : Maybe a -> Maybe a -> Maybe a
mappend x y = case (x, y) of
  (Just v, _)  -> Just v
  (Nothing, v) -> v


guard : (a -> Bool) -> a -> Maybe a
guard p x = case p x of
  False -> Nothing
  True  -> Just x


and : List Bool -> Bool
and xs = case xs of
  [] -> True
  hd :: tl -> hd && and tl


average : List Float -> Float
average xs = L.sum xs / toFloat (L.length xs)