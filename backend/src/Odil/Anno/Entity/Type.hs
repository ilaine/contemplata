{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}


module Odil.Anno.Entity.Type
( EntityType(..)
) where


import Dhall

data EntityType = EntityType
  { among :: Vector Text
  , def :: Maybe Text
  } deriving (Generic, Show)

instance Interpret EntityType
