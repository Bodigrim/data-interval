{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE CPP, ScopedTypeVariables, TypeFamilies, DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE Trustworthy #-}
{-# LANGUAGE RoleAnnotations #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.IntervalSet
-- Copyright   :  (c) Masahiro Sakai 2016, Andrew Lelechenko 2023
-- License     :  BSD-style
--
-- Maintainer  :  masahiro.sakai@gmail.com
-- Stability   :  provisional
-- Portability :  non-portable (CPP, ScopedTypeVariables, TypeFamilies, DeriveDataTypeable, MultiWayIf)
--
-- Interval datatype and interval arithmetic.
--
-----------------------------------------------------------------------------
module Data.IntervalSet
  (
  -- * IntervalSet type
    IntervalSet
  , module Data.ExtendedReal

  -- * Construction
  , whole
  , empty
  , singleton

  -- * Query
  , null
  , member
  , notMember
  , isSubsetOf
  , isProperSubsetOf
  , span

  -- * Construction
  , complement
  , insert
  , delete

  -- * Combine
  , union
  , unions
  , intersection
  , intersections
  , difference

  -- * Conversion

  -- ** List
  , fromList
  , toList

  -- ** Ordered list
  , toAscList
  , toDescList
  , fromAscList
  )
  where

import Prelude hiding (null, span)
#ifdef MIN_VERSION_lattices
import Algebra.Lattice
#endif
import Control.DeepSeq
import Data.Data
import Data.ExtendedReal
import Data.Function
import Data.Hashable
import Data.List (foldl', sortBy)
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe
import qualified Data.Semigroup as Semigroup
import Data.Interval.Internal (Interval(..), Boundary(..))
import qualified Data.Interval as Interval
#if __GLASGOW_HASKELL__ < 804
import Data.Monoid (Monoid(..))
#endif
import qualified GHC.Exts as GHCExts
import GHC.Generics (Generic)

import qualified Data.OldIntervalSet as Old

data TabStop
  = StartOpen
  | StartClosed
  | StartAndFinish
  | FinishOpen
  | FinishClosed
  | FinishAndStart
  deriving (Eq, Ord, Show, Generic)

instance NFData TabStop
instance Hashable TabStop

-- | A set comprising zero or more non-empty, /disconnected/ intervals.
--
-- Any connected intervals are merged together, and empty intervals are ignored.
data IntervalSet r = IntervalSet
  { _includesNegInf :: !Bool
  , _splitPoints    :: !(Map r TabStop)
  } deriving
    ( Eq
    , Ord
      -- ^ Note that this Ord is derived and not semantically meaningful.
      -- The primary intended use case is to allow using 'IntervalSet'
      -- in maps and sets that require ordering.
    , Typeable
    )

type role IntervalSet nominal

toOld :: Ord r => IntervalSet r -> Old.IntervalSet r
toOld = Old.fromAscList . toAscList

fromOld :: Ord r => Old.IntervalSet r -> IntervalSet r
fromOld = fromAscDisjointList . Old.toAscList

instance (Ord r, Show r) => Show (IntervalSet r) where
  showsPrec p m = showParen (p > appPrec) $
    showString "fromList " .
    showsPrec (appPrec+1) (toAscList m)

instance (Ord r, Read r) => Read (IntervalSet r) where
  readsPrec p =
    readParen (p > appPrec) $ \s0 -> do
      ("fromList",s1) <- lex s0
      (xs,s2) <- readsPrec (appPrec+1) s1
      return (fromList xs, s2)

appPrec :: Int
appPrec = 10

-- This instance preserves data abstraction at the cost of inefficiency.
-- We provide limited reflection services for the sake of data abstraction.

instance (Ord r, Data r) => Data (IntervalSet r) where
  gfoldl k z x   = z fromList `k` toList x
  toConstr _     = fromListConstr
  gunfold k z c  = case constrIndex c of
    1 -> k (z fromList)
    _ -> error "gunfold"
  dataTypeOf _   = setDataType
  dataCast1 f    = gcast1 f

fromListConstr :: Constr
fromListConstr = mkConstr setDataType "fromList" [] Prefix

setDataType :: DataType
setDataType = mkDataType "Data.IntervalSet.IntervalSet" [fromListConstr]

instance NFData r => NFData (IntervalSet r) where
  rnf (IntervalSet b m) = b `seq` rnf m

instance Hashable r => Hashable (IntervalSet r) where
  hashWithSalt s (IntervalSet r m) = s `hashWithSalt` r `hashWithSalt` Map.assocs m

#ifdef MIN_VERSION_lattices
#if MIN_VERSION_lattices(2,0,0)

instance (Ord r) => Lattice (IntervalSet r) where
  (\/) = union
  (/\) = intersection

instance (Ord r) => BoundedJoinSemiLattice (IntervalSet r) where
  bottom = empty

instance (Ord r) => BoundedMeetSemiLattice (IntervalSet r) where
  top = whole

#else

instance (Ord r) => JoinSemiLattice (IntervalSet r) where
  join = union

instance (Ord r) => MeetSemiLattice (IntervalSet r) where
  meet = intersection

instance (Ord r) => Lattice (IntervalSet r)

instance (Ord r) => BoundedJoinSemiLattice (IntervalSet r) where
  bottom = empty

instance (Ord r) => BoundedMeetSemiLattice (IntervalSet r) where
  top = whole

instance (Ord r) => BoundedLattice (IntervalSet r)

#endif
#endif

instance Ord r => Monoid (IntervalSet r) where
  mempty = empty
  mappend = (Semigroup.<>)
  mconcat = unions

instance (Ord r) => Semigroup.Semigroup (IntervalSet r) where
  (<>)    = union
  stimes  = Semigroup.stimesIdempotentMonoid

lift1
  :: Ord r => (Interval r -> Interval r)
  -> IntervalSet r -> IntervalSet r
lift1 f as = fromList [f a | a <- toList as]

lift2
  :: Ord r => (Interval r -> Interval r -> Interval r)
  -> IntervalSet r -> IntervalSet r -> IntervalSet r
lift2 f as bs = fromList [f a b | a <- toList as, b <- toList bs]

instance (Num r, Ord r) => Num (IntervalSet r) where
  (+) = lift2 (+)

  (*) = lift2 (*)

  negate = lift1 negate

  abs = lift1 abs

  fromInteger i = singleton (fromInteger i)

  signum xs = fromList $ concat
    [ [ if Interval.member 0 x
        then Interval.singleton 0
        else Interval.empty
      , if Interval.null ((0 Interval.<..< inf) `Interval.intersection` x)
        then Interval.empty
        else Interval.singleton 1
      , if Interval.null ((-inf Interval.<..< 0) `Interval.intersection` x)
        then Interval.empty
        else Interval.singleton (-1)
      ]
    | x <- toList xs
    ]

-- | @recip (recip xs) == delete 0 xs@
instance forall r. (Real r, Fractional r) => Fractional (IntervalSet r) where
  fromRational r = singleton (fromRational r)
  recip xs = lift1 recip (delete (Interval.singleton 0) xs)

instance Ord r => GHCExts.IsList (IntervalSet r) where
  type Item (IntervalSet r) = Interval r
  fromList = fromList
  toList = toList

-- -----------------------------------------------------------------------

-- | whole real number line (-∞, ∞)
whole :: Ord r => IntervalSet r
whole = singleton Interval.whole

-- | empty interval set
empty :: Ord r => IntervalSet r
empty = IntervalSet False Map.empty

-- | single interval
singleton :: Ord r => Interval r -> IntervalSet r
singleton = \case
  Whole            -> IntervalSet True  Map.empty
  Empty            -> IntervalSet False Map.empty
  Point x          -> IntervalSet False (Map.singleton x StartAndFinish)
  LessThan x       -> IntervalSet True  (Map.singleton x FinishOpen)
  LessOrEqual x    -> IntervalSet True  (Map.singleton x FinishClosed)
  GreaterThan x    -> IntervalSet False (Map.singleton x StartOpen)
  GreaterOrEqual x -> IntervalSet False (Map.singleton x StartClosed)
  BothClosed x y   -> IntervalSet False (Map.fromList [(x, StartClosed), (y, FinishClosed)])
  LeftOpen x y     -> IntervalSet False (Map.fromList [(x, StartOpen), (y, FinishClosed)])
  RightOpen x y    -> IntervalSet False (Map.fromList [(x, StartClosed), (y, FinishOpen)])
  BothOpen x y     -> IntervalSet False (Map.fromList [(x, StartOpen), (y, FinishOpen)])

-- -----------------------------------------------------------------------

-- | Is the interval set empty?
null :: IntervalSet r -> Bool
null (IntervalSet b m) = not b && Map.null m

-- | Is the element in the interval set?
member :: Ord r => r -> IntervalSet r -> Bool
member x (IntervalSet b m) =
  case Map.lookupLE x m of
    Nothing -> b
    Just (r, t) -> case t of
      StartOpen      -> r /= x
      StartClosed    -> True
      StartAndFinish -> r == x
      FinishOpen     -> False
      FinishClosed   -> r == x
      FinishAndStart -> r /= x

openMember :: Ord r => r -> IntervalSet r -> Bool
openMember x (IntervalSet b m) =
  case Map.lookupLE x m of
    Nothing -> b
    Just (r, t) -> case t of
      StartOpen      -> True
      StartClosed    -> True
      StartAndFinish -> r == x
      FinishOpen     -> r == x
      FinishClosed   -> r == x
      FinishAndStart -> True

-- | Is the element not in the interval set?
notMember :: Ord r => r -> IntervalSet r -> Bool
notMember x is = not $ x `member` is

-- | Is this a subset?
-- @(is1 \``isSubsetOf`\` is2)@ tells whether @is1@ is a subset of @is2@.
isSubsetOf :: Ord r => IntervalSet r -> IntervalSet r -> Bool
isSubsetOf is1 is2 = all (`isIntervalSubsetOf` is2) (toList is1)

isIntervalSubsetOf :: Ord r => Interval r -> IntervalSet r -> Bool
isIntervalSubsetOf i is@(IntervalSet hasNegInf m) = case i of
  Whole -> hasNegInf && Map.null m
  Empty -> True
  Point x -> member x is
  LessThan x -> hasNegInf && case Map.minViewWithKey m of
    Nothing -> True
    Just ((y, _), _) -> x <= y
  LessOrEqual x -> hasNegInf && case Map.minViewWithKey m of
    Nothing -> True
    Just ((y, t), _) -> x < y || x == y && t == FinishClosed
  GreaterThan x -> hasPosInf is && case Map.maxViewWithKey m of
    Nothing -> True
    Just ((y, _), _) -> x >= y
  GreaterOrEqual x -> hasPosInf is && case Map.maxViewWithKey m of
    Nothing -> True
    Just ((y, t), _) -> x > y || x == y && t == StartClosed
  BothClosed x y -> member x is && member y is &&
    Map.null (fst (Map.split y (snd (Map.split x m))))
  LeftOpen x y -> openMember x is && member y is &&
    Map.null (fst (Map.split y (snd (Map.split x m))))
  RightOpen x y -> member x is && openMember y is &&
    Map.null (fst (Map.split y (snd (Map.split x m))))
  BothOpen x y -> openMember x is && openMember y is &&
    Map.null (fst (Map.split y (snd (Map.split x m))))

-- | Is this a proper subset? (/i.e./ a subset but not equal).
isProperSubsetOf :: Ord r => IntervalSet r -> IntervalSet r -> Bool
isProperSubsetOf is1 is2 = isSubsetOf is1 is2 && is1 /= is2

minElement :: Ord r => IntervalSet r -> Maybe (Extended r, Boundary)
minElement (IntervalSet True _) = Just (NegInf, Open)
minElement (IntervalSet False m) = case Map.minViewWithKey m of
  Nothing -> Nothing
  Just ((x, t), _) -> case t of
    StartOpen      -> Just (Finite x, Open)
    StartClosed    -> Just (Finite x, Closed)
    StartAndFinish -> Just (Finite x, Closed)
    FinishOpen     -> err
    FinishClosed   -> err
    FinishAndStart -> err
  where
    err = error "IntervalSet.minElement: violated internal invariant"

maxElement :: Ord r => IntervalSet r -> Maybe (Extended r, Boundary)
maxElement (IntervalSet hasNegInf m) = case Map.maxViewWithKey m of
  Nothing -> if hasNegInf then Just (PosInf, Open) else Nothing
  Just ((x, t), _) -> case t of
    FinishOpen     -> Just (Finite x, Open)
    FinishClosed   -> Just (Finite x, Closed)
    StartAndFinish -> Just (Finite x, Closed)
    _ -> Just (PosInf, Open)

-- | convex hull of a set of intervals.
span :: Ord r => IntervalSet r -> Interval r
span s
  | Just mn <- minElement s, Just mx <- maxElement s
  = Interval.interval mn mx
  | otherwise
  = Empty

-- -----------------------------------------------------------------------

-- | Complement the interval set.
complement :: Ord r => IntervalSet r -> IntervalSet r
complement (IntervalSet b m) = IntervalSet (not b) (Map.map f m)
  where
    f = \case
      StartOpen      -> FinishClosed
      StartClosed    -> FinishOpen
      StartAndFinish -> FinishAndStart
      FinishOpen     -> StartClosed
      FinishClosed   -> StartOpen
      FinishAndStart -> StartAndFinish

-- | Insert a new interval into the interval set.
insert :: Ord r => Interval r -> IntervalSet r -> IntervalSet r
insert i = fromOld . Old.insert i . toOld

-- | Delete an interval from the interval set.
delete :: Ord r => Interval r -> IntervalSet r -> IntervalSet r
delete i = fromOld . Old.delete i . toOld

-- | union of two interval sets
union :: Ord r => IntervalSet r -> IntervalSet r -> IntervalSet r
union is1@(IntervalSet _ m1) is2@(IntervalSet _ m2) =
  if Map.size m1 >= Map.size m2
  then foldl' (flip insert) is1 (toList is2)
  else foldl' (flip insert) is2 (toList is1)

-- | union of a list of interval sets
unions :: Ord r => [IntervalSet r] -> IntervalSet r
unions = foldl' union empty

-- | intersection of two interval sets
intersection :: Ord r => IntervalSet r -> IntervalSet r -> IntervalSet r
intersection is1 is2 = difference is1 (complement is2)

-- | intersection of a list of interval sets
intersections :: Ord r => [IntervalSet r] -> IntervalSet r
intersections = foldl' intersection whole

-- | difference of two interval sets
difference :: Ord r => IntervalSet r -> IntervalSet r -> IntervalSet r
difference is1 is2 =
  foldl' (flip delete) is1 (toList is2)

-- -----------------------------------------------------------------------

-- | Build a interval set from a list of intervals.
fromList :: Ord r => [Interval r] -> IntervalSet r
fromList = fromAscList . sortBy (compareLB `on` Interval.lowerBound')

compareLB :: Ord r => (Extended r, Boundary) -> (Extended r, Boundary) -> Ordering
compareLB (lb1, lb1in) (lb2, lb2in) =
  -- inclusive lower endpoint shuold be considered smaller
  (lb1 `compare` lb2) `mappend` (lb2in `compare` lb1in)

-- | Build a map from an ascending list of intervals.
-- /The precondition is not checked./
fromAscList :: Ord r => [Interval r] -> IntervalSet r
fromAscList = fromAscDisjointList . f
  where
    f :: Ord r => [Interval r] -> [Interval r]
    f [] = []
    f (x : xs) = g x xs
    g x [] = [x | not (Interval.null x)]
    g x (y : ys)
      | Interval.null x = g y ys
      | Interval.isConnected x y = g (x `Interval.hull` y) ys
      | otherwise = x : g y ys

fromAscDisjointList :: Ord r => [Interval r] -> IntervalSet r
fromAscDisjointList xs = IntervalSet hasNegInf (Map.fromDistinctAscList $ glueTabStops $ concatMap toTabStops xs)
  where
    hasNegInf :: Bool
    hasNegInf = case xs of
      x : _
        | NegInf <- Interval.lowerBound x
        -> True
      _ -> False

    toStartTabStop :: (Extended r, Boundary) -> Maybe (r, TabStop)
    toStartTabStop = \case
      (NegInf, _) -> Nothing
      (Finite r, Open) -> Just (r, StartOpen)
      (Finite r, Closed) -> Just (r, StartClosed)
      (PosInf, _) -> Nothing

    toFinishTabStop :: (Extended r, Boundary) -> Maybe (r, TabStop)
    toFinishTabStop = \case
      (NegInf, _) -> Nothing
      (Finite r, Open) -> Just (r, FinishOpen)
      (Finite r, Closed) -> Just (r, FinishClosed)
      (PosInf, _) -> Nothing

    toTabStops :: Interval r -> [(r, TabStop)]
    toTabStops i = maybeToList (toStartTabStop lb) ++ maybeToList (toFinishTabStop ub)
      where
        lb = Interval.lowerBound' i
        ub = Interval.upperBound' i

    glueTabStops :: Eq r => [(r, TabStop)] -> [(r, TabStop)]
    glueTabStops ((x, StartClosed) : (y, FinishClosed) : rest)
      | x == y
      = (x, StartAndFinish) : glueTabStops rest
    glueTabStops ((x, FinishOpen) : (y, StartOpen) : rest)
      | x == y
      = (x, FinishAndStart) : glueTabStops rest
    glueTabStops (x : rest) = x : glueTabStops rest
    glueTabStops [] = []

-- | Convert a interval set into a list of intervals.
toList :: Ord r => IntervalSet r -> [Interval r]
toList = toAscList

-- | Convert a interval set into a list of intervals in ascending order.
toAscList :: Ord r => IntervalSet r -> [Interval r]
toAscList (IntervalSet hasNegInf m) = (if hasNegInf then f (NegInf, Open) else g) (Map.assocs m)
  where
    f lb [] = [Interval.interval lb (PosInf, Open)]
    f lb ((x, t) : xs) = case t of
      StartOpen      -> err
      StartClosed    -> err
      StartAndFinish -> err
      FinishOpen     -> Interval.interval lb (Finite x, Open) : g xs
      FinishClosed   -> Interval.interval lb (Finite x, Closed) : g xs
      FinishAndStart -> Interval.interval lb (Finite x, Open) : f (Finite x, Open) xs

    g [] = []
    g ((x, t) : xs) = case t of
      StartOpen      -> f (Finite x, Open) xs
      StartClosed    -> f (Finite x, Closed) xs
      StartAndFinish -> Interval.singleton x : g xs
      FinishOpen     -> err
      FinishClosed   -> err
      FinishAndStart -> err

    err = error "IntervalSet.toAscList: violated internal invariant"

-- | Convert a interval set into a list of intervals in descending order.
toDescList :: Ord r => IntervalSet r -> [Interval r]
toDescList s@(IntervalSet _hasNegInf m) = (if hasPosInf s then f (PosInf, Open) else g) (reverse $ Map.assocs m)
  where
    f ub [] = [Interval.interval (NegInf, Open) ub]
    f ub ((x, t) : xs) = case t of
      StartOpen      -> Interval.interval (Finite x, Open) ub : g xs
      StartClosed    -> Interval.interval (Finite x, Closed) ub : g xs
      StartAndFinish -> err
      FinishOpen     -> err
      FinishClosed   -> err
      FinishAndStart -> Interval.interval (Finite x, Open) ub : f (Finite x, Open) xs

    g [] = []
    g ((x, t) : xs) = case t of
      StartOpen      -> err
      StartClosed    -> err
      StartAndFinish -> Interval.singleton x : g xs
      FinishOpen     -> f (Finite x, Open) xs
      FinishClosed   -> f (Finite x, Closed) xs
      FinishAndStart -> err

    err = error "IntervalSet.toAscList: violated internal invariant"

hasPosInf :: IntervalSet r -> Bool
hasPosInf (IntervalSet hasNegInf m) = case Map.maxView m of
  Nothing -> hasNegInf
  Just (t, _)      -> case t of
    StartOpen      -> True
    StartClosed    -> True
    StartAndFinish -> False
    FinishOpen     -> False
    FinishClosed   -> False
    FinishAndStart -> True
