{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}


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
, fileRemoveHandler
, fileUploadHandler
, fileDownloadHandler

-- * Users
, usersHandler

-- * Utis
, isAdmin
, ifAdmin
, ifAdminSplice
, ifNotAdminSplice
) where


import           Control.Monad (when, guard, forM, (<=<))
import           Control.Monad.IO.Class (liftIO, MonadIO)
import           Control.Monad.Trans.Class (lift)
import qualified Control.Monad.Trans.State as State
import           Control.Monad.Trans.Maybe (runMaybeT, MaybeT(..))

import qualified Control.Error as Err
import qualified Control.Exception as Exc

import qualified Data.Maybe as Maybe
import qualified Data.Char as C
import qualified Data.Set as S
import qualified Data.List as L
import qualified Data.Vector as V
import qualified Data.Map.Strict as M
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BLS
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Encoding as T
import qualified Data.Configurator as Cfg
import           Data.Map.Syntax ((##))
import qualified Data.Aeson as JSON


import qualified Snap as Snap
import qualified Snap.Snaplet.Auth as Auth
import qualified Snap.Snaplet.Heist as Heist
import qualified Snap.Util.FileServe as FileServe
import qualified Snap.Util.FileUploads as Upload
import           Heist.Interpreted (bindSplices, Splice)
import           Heist (getParamNode, Splices)
import qualified Text.XmlHtml as X

import           Text.Digestive.Form (Form, (.:))
import qualified Text.Digestive.Form as D
import           Text.Digestive.Heist (bindDigestiveSplices)
import qualified Text.Digestive.Heist as H
import qualified Text.Digestive.View as D
import qualified Text.Digestive.Snap as D
import qualified Text.Digestive.Types as DT

import qualified Dhall as Dhall

import qualified Contemplata.Config as AnnoCfg
import qualified Contemplata.WebSocketServer as Server
import           Contemplata.Types
import qualified Contemplata.DB as DB
import qualified Contemplata.Users as Users

import qualified Contemplata.Ancor as Ancor
import qualified Contemplata.Ancor.Types as Ancor
import qualified Contemplata.Ancor.IO.Parse as Parse
import qualified Contemplata.Ancor.IO.Show as Show
import qualified Contemplata.Ancor.Preprocess as Pre

import qualified Auth as MyAuth
import qualified Config as MyCfg
import           Application
import           Handler.Utils (liftDB)
import           Util.Digestive (runForm)

import Debug.Trace (trace)


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
  Heist.heistLocal
    (bindSplices $ localSplices fileSet)
    (Heist.render "admin/files")
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
  let checkNewFileId fileId = liftDB $ do
        DB.hasFile fileId >>= return . \case
          True -> DT.Error "File ID already exists in the database"
          False -> DT.Success fileId
  (copyView, copyName) <- runForm
    "copy-file-form"
    "copy_button"
    ( D.validateM checkNewFileId
    $ copyFileForm (Just fileId) levels )

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
  (annoView, annoName) <- runForm
    "add-anno-form"
    "add_button"
    (addAnnoForm allAnnotators)

  case annoName of
    Nothing -> return ()
    -- Just an -> modifyAppl fileName an
    Just an -> liftDB $ DB.addAnnotator fileId an Read

  metaInfo <- liftDB $ DB.loadMeta fileId
  modifDate <- liftDB $ DB.fileModifDate fileId
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
        "modifDate" ## return
          -- [X.TextNode $ "??? " `T.append` modifDate]
          [X.TextNode modifDate]
        "removeFile" ## return
          [ X.Element "a"
            [ ("href",
               T.intercalate "/" ["admin", "file", fileIdTxt, "remove"])
            , ("title", "Click to remove the file from the database") ]
            [X.TextNode "Remove"]
          ]
        "downloadFile" ## return
          [ X.Element "a"
            [ ("href",
               T.intercalate "/" ["admin", "json", fileIdTxt])
            , ("title", "Click to see the raw JSON file") ]
            [X.TextNode "Show JSON"]
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
copyFileForm
  :: Maybe FileId
     -- ^ The source file ID (if any)
  -> [T.Text]
     -- ^ The list of annotation levels
  -> Form T.Text AppHandler FileId
copyFileForm fileId levels = finalize $ FileId
  <$> "file-name" .: D.text (fileName <$> fileId)
  -- TODO: setting the default annotation level does not seem to work.
  -- Nor the commented out version below.
  <*> "file-level" .: D.choice (map double levels) (annoLevel <$> fileId)
--   <*> "file-level" .: D.choice'
--     (log $ map double levels)
--     (log $ levelIndex =<< annoLevel <$> fileId)
  <*> "file-id" .: D.text Nothing
  where
    finalize
      = D.validate checkColons
    checkColons fileId@FileId{..} = 
      if all correct [fileName, annoLevel, copyId]
         then DT.Success fileId
         else DT.Error $ T.unwords
           [ "File name components (base name, ID) can only"
           , "contain alphanumeric characters, '_', and '-'" ]
    -- hasColon = Maybe.isJust . T.find (==':')
    correct = T.all (\c -> C.isAlphaNum c || c `elem` ['_', '-'])
    double x = (x, x)
--     levelIndex level = L.findIndex (==level) levels
--     log x = trace (show x) x


---------------------------------------
-- File removal handler
---------------------------------------


fileRemoveHandler :: AppHandler ()
fileRemoveHandler = ifAdmin $ do

  Just fileIdBS <- Snap.getParam "filename"
  let fileIdTxt = T.decodeUtf8 fileIdBS
  Just fileId <- return $ decodeFileId fileIdTxt

  (rmView, rmData) <- D.runForm "remove-file-form" removeFileForm

  case rmData of
    Nothing -> return ()
    Just () -> do
      liftDB $ DB.removeFile fileId
      redirectToFiles

  let localSplices = do
        "fileName" ## return
          [X.TextNode fileIdTxt]

  Heist.heistLocal
    ( bindDigestiveSplices rmView
    . bindSplices localSplices )
    (Heist.render "admin/remove")


-- | File removal form.  Nothing there for the moment.
removeFileForm :: Form T.Text AppHandler ()
removeFileForm = pure ()


---------------------------------------
-- File dowload handler
---------------------------------------


fileDownloadHandler :: AppHandler ()
fileDownloadHandler = ifAdmin $ do
  Just fileIdTxt <- fmap T.decodeUtf8 <$> Snap.getParam "filename"
  Just fileId <- return $ decodeFileId fileIdTxt
  filePath <- liftDB $ DB.storeFilePath fileId
  -- FileServe.serveFileAs "application/json" filePath
  FileServe.serveFile filePath


---------------------------------------
-- File upload handler
---------------------------------------


fileUploadHandler :: AppHandler ()
fileUploadHandler = ifAdmin $ do

  -- TODO: the fragment of code below is also in the `fileHandler`
  snapCfg <- Snap.getSnapletUserConfig
  levels <- liftIO $ do
    Just cfgPath <- Cfg.lookup snapCfg "anno-config"
    cfg <- Dhall.input Dhall.auto cfgPath
    return . map TL.toStrict . V.toList . AnnoCfg.annoLevels $ cfg

  let mb32 = (2 ^ (20::Int)) * 32 -- 32 MB
  (uploadView, uploadData) <- D.runFormWith
    ( D.defaultSnapFormConfig
      { D.uploadPolicy =
          Upload.setMaximumFormInputSize mb32
          Upload.defaultUploadPolicy
      , D.partPolicy = const $
          Upload.allowWithMaximumSize mb32
      }
    )
    "upload-file-form"
    (uploadFileForm levels)

  localSplices <- case uploadData of
    Just Upload{..} -> do
      liftDB $ do
        DB.saveFile fileId defaultMeta fileToUpload
      return $ do
        "successMessage" ## return
          [ X.Element "div" [("class", "alert alert-success")]
            [X.TextNode "File successfully uploaded"]
          ]
    _ -> return $ "successMessage" ## return []

  Heist.heistLocal
    ( bindDigestiveSplices uploadView
    . bindSplices localSplices )
    (Heist.render "admin/upload")


-- | The upload form.
data Upload a = Upload
  { fileId :: FileId
  , fileToUpload :: a
  , forceUpload :: Bool
  , ancorFormat :: Bool
  , removePhatics :: Bool
  }


-- | Upload file form.
uploadFileForm
  :: [T.Text]
  -> Form T.Text AppHandler (Upload File)
uploadFileForm levels =
  finalize $ Upload
    <$> copyFileForm Nothing levels
    <*> "file-path" .: D.validate checkFile D.file
    <*> "enforce" .: D.bool (Just False)
    <*> "ancor" .: D.bool (Just False)
    <*> "rmPhatics" .: D.bool (Just True)
  where
    finalize
      = D.validateM decodeFile
      . D.validateM checkNewFileId
    checkFile = \case
      Nothing -> DT.Error "You must specify a file to upload (size limit = 32MB)"
      Just filePath -> DT.Success filePath
    checkNewFileId upl@Upload{..}
      | forceUpload = return $ DT.Success upl
      | otherwise = liftDB $ do
          DB.hasFile fileId >>= return . \case
            True -> DT.Error "File ID already exists in the database"
            False -> DT.Success upl
    decodeFile upl@Upload{..}
      | ancorFormat = do
          rmPath <- case removePhatics of
            False -> return Nothing
            True -> do
              snapCfg <- Snap.getSnapletUserConfig
              liftIO $ Cfg.lookup snapCfg "remove"
          let ioAncor = T.readFile fileToUpload
          liftIO (Ancor.processAncor rmPath ioAncor) >>= return . \case
            Left err -> DT.Error err
            Right file -> DT.Success $ upl {fileToUpload = file}
      | otherwise = liftDB $ do
          cts <- liftIO $ BLS.readFile fileToUpload
          return $ case JSON.eitherDecode' cts of
            Left err -> DT.Error . T.pack $ "Invalid file format: " ++ err
            Right file -> DT.Success $ upl {fileToUpload = file}


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


redirectToFiles :: AppHandler ()
redirectToFiles = do
  hrefBase <- do
    cfg <- Snap.getSnapletUserConfig
    liftIO $ MyCfg.fromCfg' cfg "href-base"
  let middlePath =
        ( if "/" `BS.isSuffixOf` hrefBase
          then "" else "/" )
        `BS.append` "admin/files"
  Snap.redirect $ BS.concat
    [ hrefBase
    , middlePath ]


---------------------------------------
-- Users handler
---------------------------------------


usersHandler :: AppHandler ()
usersHandler = ifAdmin $ do

  (userView, userData) <-
    D.runForm "add-user-form" . addUserForm . S.fromList =<< getAnnoList

  successSplice <- case userData of
    Nothing -> return $ "successMessage" ## return []
    -- Create new user
    Just (login, pass, False) -> do
      res <- Snap.with auth $ Auth.createUser login (T.encodeUtf8 pass)
      case res of
        Left err -> do
          Snap.writeText . T.pack $ show res
          return $ "successMessage" ## return []
        Right _  ->
          return $ do
            "successMessage" ## return
              [ X.Element "div" [("class", "alert alert-success")]
                [X.TextNode "Success"]
              ]
    -- Change the password of an existing user
    Just (login, pass, True) -> do
      Just authUser <- MyAuth.authByLogin login
      newAuthUser <- liftIO $ Auth.setPassword authUser (T.encodeUtf8 pass)
      res <- Snap.with auth $ Auth.saveUser newAuthUser
      case res of
        Left err -> do
          Snap.writeText . T.pack $ show res
          return $ "successMessage" ## return []
        Right _  ->
          return $ do
            "successMessage" ## return
              [ X.Element "div" [("class", "alert alert-success")]
                [X.TextNode "Success"]
              ]

  annoList <- getAnnoList
  Heist.heistLocal
    ( bindSplices (localSplices annoList >> successSplice)
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
addUserForm :: S.Set AnnoName -> Form T.Text AppHandler (T.Text, T.Text, Bool)
addUserForm annoSet =
  finalize $ (,,)
    <$> "user-name" .: D.text Nothing
    <*> "user-pass" .: D.text Nothing
    <*> "update"    .: D.bool (Just False)
  where
    finalize = D.validate isValid
    isValid triple@(name, pass, update)
      | update = DT.Success triple
      | otherwise =
          if name `S.member` annoSet
          then DT.Error "Login already exists"
          else DT.Success triple


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
