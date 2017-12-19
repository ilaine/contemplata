{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}


module Handler.Admin
( createUserHandler
, passwordHandler

-- * Files
, filesHandler
, fileHandler
, fileAddAnnoHandler
, fileRemoveAnnoHandler
, fileChangeAccessAnnoHandler
, fileChangeStatusHandler

-- * Users
, usersHandler

-- * Utis
, isAdmin
, ifAdmin
, ifAdminSplice
, ifNotAdminSplice
) where


import           Control.Monad.IO.Class (liftIO, MonadIO)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad (guard, (<=<))

import qualified Data.Set as S
import qualified Data.List as L
import qualified Data.Vector as V
import qualified Data.Map.Strict as M
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Encoding as T
import qualified Data.Configurator as Cfg
import           Data.Map.Syntax ((##))


import qualified Snap as Snap
import qualified Snap.Snaplet.Auth as Auth
import qualified Snap.Snaplet.Heist as Heist
import           Heist.Interpreted (bindSplices, Splice)
import           Heist (getParamNode, Splices)
import qualified Text.XmlHtml as X

import           Text.Digestive.Form (Form, (.:))
import qualified Text.Digestive.Form as D
import           Text.Digestive.Heist (bindDigestiveSplices)
import qualified Text.Digestive.Heist as H
import qualified Text.Digestive.View as D
import qualified Text.Digestive.Snap as D

import qualified Dhall as Dhall


import qualified Odil.Config as AnnoCfg
import           Odil.Server.Types
import qualified Odil.Server.DB as DB
import qualified Odil.Server.Users as Users

import qualified Auth as MyAuth
import qualified Config as MyCfg
import           Application
import           Handler.Utils (liftDB)


---------------------------------------
-- Handlers
---------------------------------------


-- | Create user.
createUserHandler :: AppHandler ()
createUserHandler = ifAdmin $ do
  -- isAdmin
  Just login <- Snap.getParam "login"
  Just passw <- Snap.getParam "passw"
  res <- Snap.with auth $ Auth.createUser (T.decodeUtf8 login) passw
  case res of
    Left err -> Snap.writeText . T.pack $ show res
    Right _  -> Snap.writeText "Success"


-- | Change password.
passwordHandler :: AppHandler ()
passwordHandler = ifAdmin $ do
  -- isAdmin
  Just login <- Snap.getParam "login"
  Just passw <- Snap.getParam "passw"
  Just authUser <- MyAuth.authByLogin (T.decodeUtf8 login)
  authUser' <- liftIO $ Auth.setPassword authUser passw
  res <- Snap.with auth $ Auth.saveUser authUser'
  case res of
    Left err -> Snap.writeText . T.pack $ show res
    Right _  -> Snap.writeText "Success"


---------------------------------------
-- File*s* handler
---------------------------------------


filesHandler :: AppHandler ()
filesHandler = ifAdmin $ do
  fileSet <- liftDB DB.fileSet
  Heist.heistLocal (bindSplices $ localSplices fileSet) (Heist.render "admin/files")
  where
    localSplices fileSet = do
      "fileList" ## fileList (S.toList fileSet)


-- | A list of members.
fileList :: [FileId] -> Splice AppHandler
fileList =
  return . map mkElem
  where
    mkElem fileId = X.Element "li"
      [("class", "list-group-item")]
      [mkLink fileId]
    mkLink fileId = X.Element "a"
      [("href", "admin/file/" `T.append` encodeFileId fileId)]
      [X.TextNode $ encodeFileId fileId]


---------------------------------------
-- File handler
---------------------------------------


fileHandler :: AppHandler ()
fileHandler = ifAdmin $ do

  Just fileIdTxt <- fmap T.decodeUtf8 <$> Snap.getParam "filename"
  Just fileId <- return $ decodeFileId fileIdTxt

  -------------------------------------
  -- Copy file form
  -------------------------------------

  snapCfg <- Snap.getSnapletUserConfig
  levels <- liftIO $ do
    Just cfgPath <- Cfg.lookup snapCfg "anno-config"
    cfg <- Dhall.input Dhall.auto cfgPath
    return . map TL.toStrict . V.toList . AnnoCfg.annoLevels $ cfg
  (copyView, copyName) <- D.runForm
    "copy-file-form"
    (copyFileForm levels)

  case copyName of
    Nothing -> return ()
    Just newFileId -> do
      liftIO . T.putStrLn $ T.unwords
        [ "Copy", encodeFileId fileId
        , "=>", encodeFileId newFileId ]
      liftDB $ DB.copyFile fileId newFileId

  -------------------------------------
  -- Add annotator form
  -------------------------------------

  allAnnotators <- do
    cfg <- Snap.getSnapletUserConfig
    passPath <- liftIO $ MyCfg.fromCfg' cfg "password" -- "pass.json"
    liftIO $ Users.listUsers passPath
  (annoView, annoName) <- D.runForm
    "add-anno-form"
    (addAnnoForm allAnnotators)

  case annoName of
    Nothing -> return ()
    -- Just an -> modifyAppl fileName an
    Just an -> liftDB $ DB.addAnnotator fileId an Read

  metaInfo <- liftDB $ DB.loadMeta fileId
  let annotations = M.toList . annoMap $ metaInfo
      localSplices = do
        "fileName" ## return
          [X.TextNode fileIdTxt]
        "fileStatus" ## return
          [ X.Element "a"
            [ ("href",
               T.intercalate "/" ["admin", "file", fileIdTxt, "changestatus"])
            , ("title", "Click to change") ]
            [X.TextNode (T.pack . show $ fileStatus metaInfo)]
          ]
        "currentAnnotators" ## return
          (map (mkElem fileIdTxt) annotations)

  -------------------------------------
  -- Finalize
  -------------------------------------

  -- WARNING: Normally we would use `bindDigestiveSplices`, but this solution
  -- does not support several forms on a single page, it seems
  let annoSplices = digestiveSplices "anno" annoView
      copySplices = digestiveSplices "copy" copyView
      allSplices = mconcat
        -- [localSplices, annoSplices, copySplices]
        [localSplices, copySplices, annoSplices]
  Heist.heistLocal
    ( bindSplices allSplices )
    -- . bindDigestiveSplices annoView
    -- . bindDigestiveSplices copyView )
    ( Heist.render "admin/file" )

  where

    mkElem fileName (annoName, access) = X.Element "tr" []
        [ mkText annoName
        , mkLink "remove" "Click to remove" $
          T.intercalate "/" ["admin", "file", fileName, "remanno", annoName]
        , mkLink (T.pack $ show access) "Click to change" $
          T.intercalate "/" ["admin", "file", fileName, "changeaccess", annoName]
        ]

    mkText x = X.Element "td" [] [X.TextNode x]
    mkLink x tip href = X.Element "td" [] [X.Element "a"
        [ ("href", href)
        , ("title", tip) ]
        [X.TextNode x] ]


-- | Add annotator form.
addAnnoForm :: [T.Text] -> Form T.Text AppHandler T.Text
addAnnoForm anns =
  let double x = (x, x)
  in  "anno-name" .: D.choice (map double anns) Nothing


-- | Copy file form.
copyFileForm :: [T.Text] -> Form T.Text AppHandler FileId
copyFileForm levels = FileId
  <$> "file-name" .: D.text Nothing
  <*> "file-level" .: D.choice (map double levels) Nothing
  <*> "file-id" .: D.text Nothing
  where
    double x = (x, x)


---------------------------------------
-- File modification handlers
---------------------------------------


-- | Add annotator to a file handler.
fileAddAnnoHandler :: AppHandler ()
fileAddAnnoHandler = ifAdmin $ do
  Just fileNameBS <- Snap.getParam "filename"
  Just fileName <- (return . decodeFileId) (T.decodeUtf8 fileNameBS)
  Just annoName <- fmap T.decodeUtf8 <$> Snap.getParam "annoname"
  liftDB $ DB.addAnnotator fileName annoName Read
  redirectToFile fileNameBS


-- | Remmove annotator from a file handler.
fileRemoveAnnoHandler :: AppHandler ()
fileRemoveAnnoHandler = ifAdmin $ do
  Just fileNameBS <- Snap.getParam "filename"
  Just fileName <- (return . decodeFileId) (T.decodeUtf8 fileNameBS)
  Just annoName <- fmap T.decodeUtf8 <$> Snap.getParam "annoname"
  liftDB $ DB.remAnnotator fileName annoName
  redirectToFile fileNameBS


-- | Remmove annotator from a file handler.
fileChangeAccessAnnoHandler :: AppHandler ()
fileChangeAccessAnnoHandler = ifAdmin $ do
  Just fileNameBS <- Snap.getParam "filename"
  Just fileName <- (return . decodeFileId) (T.decodeUtf8 fileNameBS)
  Just annoName <- fmap T.decodeUtf8 <$> Snap.getParam "annoname"
  liftDB $ DB.changeAccessAnnotator fileName annoName
  redirectToFile fileNameBS


-- | Remmove annotator from a file handler.
fileChangeStatusHandler :: AppHandler ()
fileChangeStatusHandler = ifAdmin $ do
  Just fileNameBS <- Snap.getParam "filename"
  Just fileName <- (return . decodeFileId) (T.decodeUtf8 fileNameBS)
  liftDB . DB.changeStatus fileName $ \case
    New -> Touched
    Touched -> Done
    Done -> New
  redirectToFile fileNameBS


redirectToFile :: BS.ByteString -> AppHandler ()
redirectToFile fileNameBS = do
  hrefBase <- do
    cfg <- Snap.getSnapletUserConfig
    liftIO $ MyCfg.fromCfg' cfg "href-base"
  let middlePath =
        ( if "/" `BS.isSuffixOf` hrefBase
          then "" else "/" )
        `BS.append` "admin/file/"
  Snap.redirect $ BS.concat
    [ hrefBase
    , middlePath
    , fileNameBS ]


---------------------------------------
-- Users handler
---------------------------------------


usersHandler :: AppHandler ()
usersHandler = ifAdmin $ do

  (userView, userData) <-
    D.runForm "add-user-form" . addUserForm . S.fromList =<< getAnnoList

  case userData of
    Nothing -> return ()
    Just (login, pass) -> do
      res <- Snap.with auth $ Auth.createUser login (T.encodeUtf8 pass)
      case res of
        Left err -> Snap.writeText . T.pack $ show res
        Right _  -> return () -- Snap.writeText "Success"

  annoList <- getAnnoList
  Heist.heistLocal
    ( bindSplices (localSplices annoList)
    . bindDigestiveSplices userView )
    (Heist.render "admin/users")

  where

    localSplices annoList = do
      "userList" ## userList annoList

    getAnnoList = do
      cfg <- Snap.getSnapletUserConfig
      passPath <- liftIO $ MyCfg.fromCfg' cfg "password"
      liftIO $ Users.listUsers passPath


-- | A list of members.
userList :: [AnnoName] -> Splice AppHandler
userList =
  return . map mkElem
  where
    mkElem anno = X.Element "li"
      [("class", "list-group-item")]
      [X.TextNode anno]


-- | Login form for a user.
addUserForm :: S.Set AnnoName -> Form T.Text AppHandler (T.Text, T.Text)
addUserForm annoSet = (,)
  <$> "user-name" .:
              D.check "Login already exists"
              (not . (`S.member` annoSet))
              (D.text Nothing)
  <*> "user-pass" .: D.text Nothing


---------------------------------------
-- DB utils
---------------------------------------


---------------------------------------
-- Digestive utils
---------------------------------------


digestiveSplices
  :: MonadIO m
  => T.Text -- ^ The prefix of the form
  -> D.View T.Text
  -> Splices (Splice m)
digestiveSplices prefix view = do
    prefix#"Input"            ## H.dfInput view
    prefix#"InputList"        ## H.dfInputList view
    prefix#"InputText"        ## H.dfInputText view
    prefix#"InputTextArea"    ## H.dfInputTextArea view
    prefix#"InputPassword"    ## H.dfInputPassword view
    prefix#"InputHidden"      ## H.dfInputHidden view
    prefix#"InputSelect"      ## H.dfInputSelect view
    prefix#"InputSelectGroup" ## H.dfInputSelectGroup view
    prefix#"InputRadio"       ## H.dfInputRadio view
    prefix#"InputCheckbox"    ## H.dfInputCheckbox view
    prefix#"InputFile"        ## H.dfInputFile view
    prefix#"InputSubmit"      ## H.dfInputSubmit view
    prefix#"Label"            ## H.dfLabel view
    prefix#"Form"             ## H.dfForm view
    prefix#"ErrorList"        ## H.dfErrorList view
    prefix#"ChildErrorList"   ## H.dfChildErrorList view
    prefix#"SubView"          ## H.dfSubView view
    prefix#"IfChildErrors"    ## H.dfIfChildErrors view
      where
        (#) = T.append


---------------------------------------
-- Utils
---------------------------------------


-- | Verify that the admin is logged in.
isAdmin :: AppHandler Bool
isAdmin = do
  cfg <- Snap.getSnapletUserConfig
  adminLogin <- liftIO $ MyCfg.fromCfg' cfg "admin"
  --
  -- NOTE: this handler must not fail because it is used in
  -- the splice `ifAdminSplce`! Hence we need to explicitely
  -- handle the `Nothing` value, and not with pattern matching.
  --
  -- Just current <- Snap.with auth Auth.currentUser
  -- return $ adminLogin == Auth.userLogin current
  --
  currentMay <- Snap.with auth Auth.currentUser
  return $ case currentMay of
    Nothing -> False
    Just current -> adminLogin == Auth.userLogin current


-- | Verify that the admin is logged in.
ifAdmin :: AppHandler () -> AppHandler ()
ifAdmin after = do
  cfg <- Snap.getSnapletUserConfig
  adminLogin <- liftIO $ MyCfg.fromCfg' cfg "admin"
  Just current <- Snap.with auth Auth.currentUser
  if adminLogin == Auth.userLogin current
    then after
    else Snap.writeText "Not authorized"


-- | Run the contents of the node if the logged user has
-- administrative rights.
ifAdminSplice :: Splice AppHandler
ifAdminSplice = lift isAdmin >>= \case
  False -> return []
  True -> X.childNodes <$> getParamNode


-- | Run the contents of the node if the logged user has no
-- administrative rights.
ifNotAdminSplice :: Splice AppHandler
ifNotAdminSplice = lift isAdmin >>= \case
  True -> return []
  False -> X.childNodes <$> getParamNode
