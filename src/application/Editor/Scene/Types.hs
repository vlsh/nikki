{-# language NamedFieldPuns, FlexibleInstances #-}

module Editor.Scene.Types where


import Utils

-- import Data.Map hiding (map, filter)
import Data.SelectTree
import qualified Data.Indexable as I
import Data.Indexable hiding (length, toList, findIndices, fromList, empty)
import Data.Menu hiding (selected)

import Control.Monad.State
-- import Control.Exception

import Graphics.Qt

-- import Base.Sprited
import Base.Grounds

import Object.Types


data EditorScene
    = EditorScene {
        levelName :: Maybe String,

        cursor :: EditorPosition,
        cursorStep :: EditorScene -> EditorPosition,

        sorts :: SelectTree Sort_,

        objects :: Grounds EditorObject,
        selectedLayer :: GroundsIndex,
        selected :: Maybe Index,
            -- index of the object that is in the scene and currently under the cursor
            -- (in the selected layer)

        debugMsgs :: [String]
    }
    | TerminalScene {
        mainScene :: EditorScene,
        tmAvailableRobots :: [Index],
        tmTerminalIndex :: Index,
        tmSelectedRobots :: [Index],

        debugMsgs :: [String]
    }
    | MenuScene {
        mainScene :: EditorScene,
        menu :: Menu MenuLabel EditorScene,

        debugMsgs :: [String]
      }
    | FinalState {
        mainScene :: EditorScene,

        debugMsgs :: [String]
      }
  deriving Show

instance Show (EditorScene -> EditorPosition) where
    show _ = "<EditorScene -> EditorPosition>"


getLevelName :: EditorScene -> Maybe String
getLevelName EditorScene{levelName} = levelName
getLevelName TerminalScene{} =
    e "saving from TerminalScene NYI. Note: is the mainScene already changed?"
getLevelName MenuScene{mainScene} = levelName mainScene
getLevelName FinalState{mainScene} = levelName mainScene

getCursorStep :: EditorScene -> EditorPosition
getCursorStep s = cursorStep s s

data MenuLabel = MenuLabel (Maybe Sort_) String
  deriving (Show)

data ControlData = ControlData [QtEvent] [Key]
  deriving Show

type SceneMonad = StateT EditorScene IO


-- * getters

-- | get the object that is actually selected by the cursor
getSelectedObject :: EditorScene -> Maybe EditorObject
getSelectedObject EditorScene{selected = Just i, objects, selectedLayer} =
    Just (content (objects !|| selectedLayer) !!! i)
getSelectedObject EditorScene{selected = Nothing} = Nothing

-- | returns all Indices (to the mainLayer) for robots
getRobotIndices :: EditorScene -> [Index]
getRobotIndices EditorScene{objects} =
    I.findIndices (isRobot . snd) $ content $ mainLayer objects

getCursorSize :: EditorScene -> (Size Int)
getCursorSize s@EditorScene{} =
    size_ $ getSelected $ sorts s
getCursorSize s@TerminalScene{} = getCursorSize $ mainScene s

getObject :: EditorScene -> Index -> EditorObject
getObject scene@TerminalScene{} i = os !!! i
  where
    os = mainLayerIndexable $ objects $ mainScene scene

getTerminalMRobot :: EditorScene -> Maybe EditorObject
getTerminalMRobot scene@TerminalScene{} =
    case tmAvailableRobots scene of
        (i : _) -> Just (getObject scene i)
        [] -> Nothing


-- * Setters


addDebugMsg :: String -> EditorScene -> EditorScene
addDebugMsg msg s =
    let msgs = debugMsgs s
    in s{debugMsgs = msg : msgs}

-- | adds a new default Layer to the EditorScene
addDefaultBackground :: EditorScene -> EditorScene
addDefaultBackground s@EditorScene{objects = (Grounds backgrounds mainLayer foregrounds)} =
    s{objects = objects'}
  where
    objects' = Grounds (backgrounds >: initialLayer) mainLayer foregrounds

-- | adds a new default Layer to the EditorScene
addDefaultForeground :: EditorScene -> EditorScene
addDefaultForeground s@EditorScene{objects = (Grounds backgrounds mainLayer foregrounds)} =
    s{objects = objects'}
  where
    objects' = Grounds backgrounds mainLayer (initialLayer <: foregrounds)

-- * modification

modifyObjects :: (Grounds EditorObject -> Grounds EditorObject) -> EditorScene -> EditorScene
modifyObjects f s@EditorScene{objects} = s{objects = f objects}

modifySorts :: (SelectTree Sort_ -> SelectTree Sort_) -> EditorScene -> EditorScene
modifySorts f scene@EditorScene{sorts} = scene{sorts = f sorts}

