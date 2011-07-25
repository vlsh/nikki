{-# language GeneralizedNewtypeDeriving, DeriveDataTypeable, NamedFieldPuns,
     ViewPatterns #-}

-- | module for a Bag of indexed things. 
-- They have an order (can be converted to a list.)
-- imports could look like this:
--
-- import qualified Data.Indexable as I
-- import Data.Indexable hiding (length, toList, findIndices, fromList, empty)

module Data.Indexable (
    Indexable(..),
    Index(..),
    keys,

    Data.Indexable.length,
    Data.Foldable.toList,
    (!!!),
    Data.Indexable.findIndices,
    Data.Indexable.filter,
    Data.Indexable.catMaybes,
    sortBy,

    Data.Indexable.fromList,
    (<:),
    (>:),
    insert,

    fmapMWithIndex,

    deleteByIndex,
    indexA,
    toHead,
    toLast,
    isIndexOf,

    optimizeMerge,
  ) where

import Prelude hiding (map, mapM, (++), filter, reverse, elem, maximum, zip, zipWith, null, length, head, tail)

import qualified Data.List as List
import Data.Accessor
import Data.Foldable (Foldable(..), foldMap, toList)
import Data.Initial
import Data.Traversable (Traversable, traverse)
import Data.Vector as Vector
import Data.Generics (Typeable, Data)
import Data.Maybe

import Control.Arrow

import Utils


newtype Index = Index {index :: Int}
  deriving (Show, Read, Enum, Num, Eq, Integral, Real, Ord, Data, Typeable)


-- | invariants:
-- sort (keys x) == sort (Map.keys (values x))
-- nub (keys x) == keys x
-- const True (keys x == sort (keys x))  (that is, the keys may be unsorted)
data Indexable a =
    Indexable {
        values :: (Vector (Index, a))
      }
  deriving (Eq, Typeable, Data)

instance Show a => Show (Indexable a) where
    show (Indexable v) = "Indexable " List.++ show (Vector.toList v)

instance Read a => Read (Indexable a) where
    readsPrec n s =
        if consString `List.isPrefixOf` s then
            List.map (first (Indexable . Vector.fromList)) $
                readsPrec n (List.drop (List.length consString) s)
        else
            error "Data.Indexable.readsPrec: not parseable"
      where
        consString = "Indexable "

keysVector :: Indexable a -> Vector Index
keysVector = map fst . values

keys :: Indexable a -> [Index]
keys = Vector.toList . keysVector



-- * instances

instance Functor Indexable where
    fmap f (Indexable values) = Indexable (fmap (second f) values)

instance Foldable Indexable where
    foldMap f (Indexable values) =
        foldMap (f . snd) values

instance Traversable Indexable where
    traverse cmd (Indexable values) =
        Indexable <$> traverse inner values
      where
        inner (k, v) = tuple k <$> cmd v

fmapMWithIndex :: (Monad m, Functor m) => (Index -> a -> m b)
    -> Indexable a -> m (Indexable b)
fmapMWithIndex cmd (Indexable values) = 
    Indexable <$> mapM (\ (i, v) -> tuple i <$> cmd i v) values

instance Initial (Indexable a) where
    initial = Indexable empty

-- * getter

-- | returns the length of the contained list
length :: Indexable a -> Int
length = Vector.length . values

-- -- | returns, if the Index points to something
isIndexOf :: Index -> Indexable a -> Bool
isIndexOf i indexable = i `elem` keysVector indexable

(!!!) :: Indexable a -> Index -> a
(Indexable values) !!! i =
    case find ((== i) . fst) values of
        Just x -> snd x
        Nothing -> error ("!!!: Index not found")

-- | returns the list of indices for which the corresponding
-- values fullfill a given predicate.
-- Honours the order of values.
findIndices :: (a -> Bool) -> Indexable a -> [Index]
findIndices p (Indexable values) =
    Vector.toList $ map fst $ Vector.filter (p . snd) values

filter :: (a -> Bool) -> Indexable a -> Indexable a
filter p (Indexable values) =
    Indexable $ Vector.filter (p . snd) values

catMaybes :: Indexable (Maybe a) -> Indexable a
catMaybes = Data.Indexable.filter isJust >>> fmap fromJust

-- | Stable sorting of Indexables while preserving indices.
sortBy :: (a -> a -> Ordering) -> Indexable a -> Indexable a
sortBy ordering (Indexable values) =
    Indexable $ Vector.fromList $ List.sortBy (ordering `on` snd) $ Vector.toList values

-- | generate an unused Index
-- (newIndex l) `elem` l == False
newIndex :: Vector Index -> Index
newIndex l = if null l then 0 else maximum l + 1

-- * constructors

(<:) :: a -> Indexable a -> Indexable a
a <: (Indexable values) =
    Indexable ((i, a) `cons` values)
  where
    i = newIndex $ map fst values

(>:) :: Indexable a -> a -> Indexable a
(Indexable values) >: a =
    Indexable (values `snoc` (i, a))
  where
    i = newIndex $ map fst values

-- | inserts an element (at the end) and returns the new Index
insert :: a -> Indexable a -> (Index, Indexable a)
insert a (Indexable values) =
    (i, Indexable ((i, a) `cons` values))
  where
    i = newIndex $ map fst values

fromList :: [a] -> Indexable a
fromList list = Indexable $ Vector.fromList (List.zip [0 ..] list)

-- * mods

deleteByIndex :: Index -> Indexable a -> Indexable a
deleteByIndex i (Indexable values) =
    Indexable $ Vector.filter (fst >>> (/= i)) values

indexA :: Index -> Accessor (Indexable a) a
indexA i = accessor getter setter
  where
    getter ix = ix !!! i
    setter e (Indexable values) = Indexable $ update values (Vector.singleton (foundVectorIndex, (i, e)))
      where
        (Just foundVectorIndex) = findIndex (fst >>> (== i)) values

-- | Puts the indexed element first.
-- Unsafe when Index not contained.
-- OPT: Vector-like?
toHead :: Index -> Indexable a -> Indexable a
toHead i (Indexable values) =
    Indexable $ inner empty values
  where
    inner :: Vector (Index, a) -> Vector (Index, a) -> Vector (Index, a)
    inner akk vector = case decons vector of
        Just (a, r) ->
            if fst a == i then
                a `cons` reverse akk ++ r
            else
                inner (a `cons` akk) r

-- | Puts the indexed element last.
-- Unsafe when Index not contained.
toLast :: Index -> Indexable a -> Indexable a 
toLast i (Indexable values) =
    Indexable $ inner empty values
  where
    inner :: Vector (Index, a) -> Vector (Index, a) -> Vector (Index, a)
    inner akk vector = case decons vector of
        Just (a, r) ->
            if fst a == i then
                reverse akk ++ r `snoc` a
            else
                inner (a `cons` akk) r


type MergeVector a = Vector (Either (Index, a) a) -- left unmerged, right merged

-- | optimizes an Indexable with merging.
-- calls the given function for every pair in the Indexable.
-- the given function returns Nothing, if nothing can be optimized and
-- returns the replacement for the optimized pair.
-- The old pair will be replaced with dummy elements.
-- This function is idempotent. (if that's an english word)
-- Note, that indices of optimized items are going to be invalidated.
optimizeMerge :: Show a => (a -> a -> Maybe a) -> Indexable a -> Indexable a
optimizeMerge p =
    convertToVector >>> fixpoint (mergeVectorSome p) >>> convertToIndexable
  where
    fixpoint :: (MergeVector a -> MergeVector a) -> MergeVector a -> MergeVector a
    fixpoint f vector =
        let r = f vector
        in if Vector.length r == Vector.length vector then 
            vector
          else
            fixpoint f r


    convertToVector :: Indexable a -> MergeVector a -- left unmerged, right merged
    convertToVector ix = map Left $ values ix
    convertToIndexable :: MergeVector a -> Indexable a
    convertToIndexable list =
        Indexable $ zipWith inner list newIndices
      where
        newIndices :: Vector Index
        newIndices = Vector.fromList $
            if null allIndices then [0 ..] else [maximum allIndices + 1 ..]
        allIndices = map fst $ lefts list
        inner (Left x) _ = x
        inner (Right x) i = (i, x)

-- OPT: This is probably not very Vector-like code.
mergeVectorSome :: (a -> a -> Maybe a) -> MergeVector a -> MergeVector a
mergeVectorSome p vector = case decons vector of
    Just (a, r) ->
        case mergeSome p a (empty, r) of
            Just (merged, r') -> Right merged `cons` mergeVectorSome p r'
            Nothing -> a `cons` mergeVectorSome p r
    Nothing -> empty
  where
    mergeSome :: (a -> a -> Maybe a) -> Either (Index, a) a -> (MergeVector a, MergeVector a)
        -> Maybe (a, MergeVector a)
    mergeSome p outerA (before, after) = case decons after of
        Just (outerB, r) ->
            case p (getInner outerA) (getInner outerB) of
                Just x -> Just (x, reverse before ++ r)
                Nothing -> mergeSome p outerA (outerB `cons` before, r)
        Nothing -> Nothing

    getInner (Left (_, a)) = a
    getInner (Right b) = b


-- * vector utils (instances stolen from hackage: vector-instances)

lefts :: Vector (Either a b) -> Vector a
lefts = Vector.filter isLeft >>> map fromLeft
  where
    isLeft (Left _) = True
    isLeft _ = False
    fromLeft (Left a) = a

-- | (head a, tail a) for mimicking (a : r) pattern matching
decons :: Vector a -> Maybe (a, Vector a)
decons v =
    if null v then Nothing else Just (head v, tail v)

instance Traversable Vector where
    traverse f v
        = Vector.fromListN (Vector.length v) <$> traverse f (Vector.toList v)
    {-# INLINE traverse #-}

instance Functor Vector where
    fmap = Vector.map
    {-# INLINE fmap #-}

instance Foldable Vector where
    foldl = Vector.foldl
    {-# INLINE foldl #-}
    foldr = Vector.foldr
    {-# INLINE foldr #-}
    foldl1 = Vector.foldl1
    {-# INLINE foldl1 #-}
    foldr1 = Vector.foldr1
    {-# INLINE foldr1 #-}
