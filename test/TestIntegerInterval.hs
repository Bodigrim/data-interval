{-# LANGUAGE TemplateHaskell, ScopedTypeVariables #-}
import Control.Monad
import Data.Maybe
import Data.Ratio
import Test.HUnit hiding (Test)
import Test.QuickCheck
import Test.Framework (Test, defaultMain, testGroup)
import Test.Framework.TH
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2

import Data.IntegerInterval
  ( IntegerInterval, Extended (..), (<=..<=), (<=..<), (<..<=), (<..<)
  , (<!), (<=!), (==!), (>=!), (>!), (/=!)
  , (<?), (<=?), (==?), (>=?), (>?), (/=?)
  , (<??), (<=??), (==??), (>=??), (>??), (/=??)
  )
import qualified Data.IntegerInterval as IntegerInterval
import Data.Interval (Interval)
import qualified Data.Interval as Interval

{--------------------------------------------------------------------
  empty
--------------------------------------------------------------------}

prop_empty_is_bottom =
  forAll integerIntervals $ \a ->
    IntegerInterval.isSubsetOf IntegerInterval.empty a

prop_null_empty =
  forAll integerIntervals $ \a ->
    IntegerInterval.null a == (a == IntegerInterval.empty)

case_null_empty =
  IntegerInterval.null (IntegerInterval.empty :: IntegerInterval) @?= True

{--------------------------------------------------------------------
  whole
--------------------------------------------------------------------}

prop_whole_is_top =
  forAll integerIntervals $ \a ->
    IntegerInterval.isSubsetOf a IntegerInterval.whole

case_nonnull_top =
  IntegerInterval.null (IntegerInterval.whole :: IntegerInterval) @?= False

{--------------------------------------------------------------------
  singleton
--------------------------------------------------------------------}

prop_singleton_member =
  forAll arbitrary $ \r ->
    IntegerInterval.member (r::Integer) (IntegerInterval.singleton r)

prop_singleton_member_intersection =
  forAll integerIntervals $ \a ->
  forAll arbitrary $ \r ->
    let b = IntegerInterval.singleton r
    in IntegerInterval.member (r::Integer) a
       ==> IntegerInterval.intersection a b == b

prop_singleton_nonnull =
  forAll arbitrary $ \r1 ->
    not $ IntegerInterval.null $ IntegerInterval.singleton (r1::Integer)

prop_distinct_singleton_intersection =
  forAll arbitrary $ \r1 ->
  forAll arbitrary $ \r2 ->
    (r1::Integer) /= r2 ==>
      IntegerInterval.intersection (IntegerInterval.singleton r1) (IntegerInterval.singleton r2)
      == IntegerInterval.empty

{--------------------------------------------------------------------
  Intersection
--------------------------------------------------------------------}

prop_intersection_comm =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.intersection a b == IntegerInterval.intersection b a

prop_intersection_assoc =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    IntegerInterval.intersection a (IntegerInterval.intersection b c) ==
    IntegerInterval.intersection (IntegerInterval.intersection a b) c

prop_intersection_unitL =
  forAll integerIntervals $ \a ->
    IntegerInterval.intersection IntegerInterval.whole a == a

prop_intersection_unitR =
  forAll integerIntervals $ \a ->
    IntegerInterval.intersection a IntegerInterval.whole == a

prop_intersection_empty =
  forAll integerIntervals $ \a ->
    IntegerInterval.intersection a IntegerInterval.empty == IntegerInterval.empty

prop_intersection_isSubsetOf =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.isSubsetOf (IntegerInterval.intersection a b) a

prop_intersection_isSubsetOf_equiv =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    (IntegerInterval.intersection a b == a)
    == IntegerInterval.isSubsetOf a b

case_intersections_empty_list = IntegerInterval.intersections [] @?= (IntegerInterval.whole :: IntegerInterval)

prop_intersections_singleton_list =
  forAll integerIntervals $ \a -> IntegerInterval.intersections [a] == a

prop_intersections_two_elems =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.intersections [a,b] == IntegerInterval.intersection a b

{--------------------------------------------------------------------
  Hull
--------------------------------------------------------------------}

prop_hull_comm =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.hull a b == IntegerInterval.hull b a

prop_hull_assoc =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    IntegerInterval.hull a (IntegerInterval.hull b c) ==
    IntegerInterval.hull (IntegerInterval.hull a b) c

prop_hull_unitL =
  forAll integerIntervals $ \a ->
    IntegerInterval.hull IntegerInterval.empty a == a

prop_hull_unitR =
  forAll integerIntervals $ \a ->
    IntegerInterval.hull a IntegerInterval.empty == a

prop_hull_whole =
  forAll integerIntervals $ \a ->
    IntegerInterval.hull a IntegerInterval.whole == IntegerInterval.whole

prop_hull_isSubsetOf =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.isSubsetOf a (IntegerInterval.hull a b)

prop_hull_isSubsetOf_equiv =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    (IntegerInterval.hull a b == b)
    == IntegerInterval.isSubsetOf a b

case_hulls_empty_list = IntegerInterval.hulls [] @?= (IntegerInterval.empty :: IntegerInterval)

prop_hulls_singleton_list =
  forAll integerIntervals $ \a -> IntegerInterval.hulls [a] == a

prop_hulls_two_elems =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    IntegerInterval.hulls [a,b] == IntegerInterval.hull a b

{--------------------------------------------------------------------
  member
--------------------------------------------------------------------}

prop_member_isSubsetOf =
  forAll arbitrary $ \r ->
  forAll integerIntervals $ \a ->
    IntegerInterval.member r a == IntegerInterval.isSubsetOf (IntegerInterval.singleton r) a

{--------------------------------------------------------------------
  isSubsetOf
--------------------------------------------------------------------}

prop_isSubsetOf_refl =
  forAll integerIntervals $ \a ->
    IntegerInterval.isSubsetOf a a

prop_isSubsetOf_trans =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    IntegerInterval.isSubsetOf a b && IntegerInterval.isSubsetOf b c
    ==> IntegerInterval.isSubsetOf a c

-- prop_isSubsetOf_antisym =
--   forAll integerIntervals $ \a ->
--   forAll integerIntervals $ \b ->
--     IntegerInterval.isSubsetOf a b && IntegerInterval.isSubsetOf b a
--     ==> a == b

{--------------------------------------------------------------------
  pickup
--------------------------------------------------------------------}

prop_pickup_member_null =
  forAll integerIntervals $ \a ->
    case IntegerInterval.pickup a of
      Nothing -> IntegerInterval.null a
      Just x -> IntegerInterval.member x a

case_pickup_empty =
  IntegerInterval.pickup (IntegerInterval.empty :: IntegerInterval) @?= Nothing

case_pickup_whole =
  isJust (IntegerInterval.pickup (IntegerInterval.whole :: IntegerInterval)) @?= True

{--------------------------------------------------------------------
  Comparison
--------------------------------------------------------------------}

case_lt_all_1 = (a <! b) @?= False
  where
    a, b :: IntegerInterval
    a = NegInf <..<= 0
    b = 0 <=..< PosInf

case_lt_all_2 = (a <! b) @?= True
  where
    a, b :: IntegerInterval
    a = NegInf <..< 0
    b = 0 <=..< PosInf

case_lt_all_3 = (a <! b) @?= True
  where
    a, b :: IntegerInterval
    a = NegInf <..<= 0
    b = 0 <..< PosInf

case_lt_all_4 = (a <! b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = 1 <=..< PosInf

case_lt_some_1 = (a <? b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = NegInf <..<= 0

case_lt_some_2 = (a <? b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <..< PosInf
    b = NegInf <..<= 0

case_lt_some_3 = (a <? b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = NegInf <..< 0

case_lt_some_4 = (a <! b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = 1 <=..< PosInf

case_le_some_1 = (a <=? b) @?= True
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = NegInf <..<= 0

case_le_some_2 = (a <=? b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <..< PosInf
    b = NegInf <..<= 0

case_le_some_3 = (a <=? b) @?= False
  where
    a, b :: IntegerInterval
    a = 0 <=..< PosInf
    b = NegInf <..< 0

prop_lt_all_not_refl =
  forAll integerIntervals $ \a -> not (IntegerInterval.null a) ==> not (a <! a)

prop_le_some_refl =
  forAll integerIntervals $ \a -> not (IntegerInterval.null a) ==> a <=? a

prop_ne_all_not_refl =
  forAll integerIntervals $ \a -> not (IntegerInterval.null a) ==> not (a /=! a)

prop_lt_all_singleton =
  forAll arbitrary $ \a ->
  forAll arbitrary $ \b ->
    (a::Integer) < b ==> IntegerInterval.singleton a <! IntegerInterval.singleton b

prop_lt_all_singleton_2 =
  forAll arbitrary $ \a ->
    not $ IntegerInterval.singleton (a::Integer) <! IntegerInterval.singleton a

prop_le_all_singleton =
  forAll arbitrary $ \a ->
  forAll arbitrary $ \b ->
    (a::Integer) <= b ==> IntegerInterval.singleton a <=! IntegerInterval.singleton b

prop_le_all_singleton_2 =
  forAll arbitrary $ \a ->
    IntegerInterval.singleton (a::Integer) <=! IntegerInterval.singleton a

prop_eq_all_singleton =
  forAll arbitrary $ \a ->
    IntegerInterval.singleton (a::Integer) ==! IntegerInterval.singleton a

prop_ne_all_singleton =
  forAll arbitrary $ \a ->
  forAll arbitrary $ \b ->
    (a::Integer) /= b ==> IntegerInterval.singleton a /=! IntegerInterval.singleton b

prop_ne_all_singleton_2 =
  forAll arbitrary $ \a ->
    not $ IntegerInterval.singleton (a::Integer) /=! IntegerInterval.singleton a

prop_lt_some_singleton =
  forAll arbitrary $ \a ->
  forAll arbitrary $ \b ->
    (a::Integer) < b ==> IntegerInterval.singleton a <? IntegerInterval.singleton b

prop_lt_some_singleton_2 =
  forAll arbitrary $ \a ->
    not $ IntegerInterval.singleton (a::Integer) <? IntegerInterval.singleton a

prop_le_some_singleton =
  forAll arbitrary $ \a ->
  forAll arbitrary $ \b ->
    (a::Integer) <= b ==> IntegerInterval.singleton a <=? IntegerInterval.singleton b

prop_le_some_singleton_2 =
  forAll arbitrary $ \a ->
    IntegerInterval.singleton (a::Integer) <=? IntegerInterval.singleton a

prop_eq_some_singleton =
  forAll arbitrary $ \a ->
    IntegerInterval.singleton (a::Integer) ==? IntegerInterval.singleton a

prop_lt_all_empty =
  forAll integerIntervals $ \a -> a <! IntegerInterval.empty

prop_lt_all_empty_2 =
  forAll integerIntervals $ \a -> IntegerInterval.empty <! a

prop_le_all_empty =
  forAll integerIntervals $ \a -> a <=! IntegerInterval.empty

prop_le_all_empty_2 =
  forAll integerIntervals $ \a -> IntegerInterval.empty <=! a

prop_eq_all_empty =
  forAll integerIntervals $ \a -> a ==! IntegerInterval.empty

prop_ne_all_empty =
  forAll integerIntervals $ \a -> a /=! IntegerInterval.empty

prop_lt_some_empty =
  forAll integerIntervals $ \a -> not (a <? IntegerInterval.empty)

prop_lt_some_empty_2 =
  forAll integerIntervals $ \a -> not (IntegerInterval.empty <? a)

prop_le_some_empty =
  forAll integerIntervals $ \a -> not (a <=? IntegerInterval.empty)

prop_le_some_empty_2 =
  forAll integerIntervals $ \a -> not (IntegerInterval.empty <=? a)

prop_eq_some_empty =
  forAll integerIntervals $ \a -> not (a ==? IntegerInterval.empty)

prop_intersect_le_some =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    not (IntegerInterval.null (IntegerInterval.intersection a b))
    ==> a <=? b

prop_intersect_eq_some =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    not (IntegerInterval.null (IntegerInterval.intersection a b))
    ==> a ==? b

prop_le_some_witness =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    case a <=?? b of
      Nothing ->
        forAll arbitrary $ \(x,y) ->
          not (IntegerInterval.member x a && IntegerInterval.member y b && x <= y)
      Just (x,y) ->
        IntegerInterval.member x a .&&. IntegerInterval.member y b .&&. x <= y

prop_lt_some_witness =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    case a <?? b of
      Nothing ->
        forAll arbitrary $ \(x,y) ->
          not (IntegerInterval.member x a && IntegerInterval.member y b && x < y)
      Just (x,y) ->
        IntegerInterval.member x a .&&. IntegerInterval.member y b .&&. x < y

prop_eq_some_witness =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    case a ==?? b of
      Nothing ->
        forAll arbitrary $ \x ->
          not (IntegerInterval.member x a && IntegerInterval.member x b)
      Just (x,y) ->
        IntegerInterval.member x a .&&. IntegerInterval.member y b .&&. x == y

prop_ne_some_witness =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    case a /=?? b of
      Nothing ->
        forAll arbitrary $ \x ->
        forAll arbitrary $ \y ->
          not (IntegerInterval.member x a && IntegerInterval.member y b && x /= y)
      Just (x,y) ->
        IntegerInterval.member x a .&&. IntegerInterval.member y b .&&. x /= y

prop_le_some_witness_forget =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    isJust (a <=?? b) == (a <=? b)

prop_lt_some_witness_forget =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    isJust (a <?? b) == (a <? b)

prop_eq_some_witness_forget =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    isJust (a ==?? b) == (a ==? b)

prop_ne_some_witness_forget =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    isJust (a /=?? b) == (a /=? b)

{--------------------------------------------------------------------
  Num
--------------------------------------------------------------------}

prop_scale_empty =
  forAll arbitrary $ \r ->
    IntegerInterval.singleton (r::Integer) * IntegerInterval.empty == IntegerInterval.empty

prop_add_comm =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    a + b == b + a

prop_add_assoc =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    a + (b + c) == (a + b) + c

prop_add_unitL =
  forAll integerIntervals $ \a ->
    IntegerInterval.singleton 0 + a == a

prop_add_unitR =
  forAll integerIntervals $ \a ->
    a + IntegerInterval.singleton 0 == a

prop_add_member =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    and [ (x+y) `IntegerInterval.member` (a+b)
        | x <- maybeToList $ IntegerInterval.pickup a
        , y <- maybeToList $ IntegerInterval.pickup b
        ]

prop_mult_comm =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    a * b == b * a

prop_mult_assoc =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    a * (b * c) == (a * b) * c

prop_mult_unitL =
  forAll integerIntervals $ \a ->
    IntegerInterval.singleton 1 * a == a

prop_mult_unitR =
  forAll integerIntervals $ \a ->
    a * IntegerInterval.singleton 1 == a

prop_mult_dist =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
  forAll integerIntervals $ \c ->
    (a * (b + c)) `IntegerInterval.isSubsetOf` (a * b + a * c)

prop_mult_empty =
  forAll integerIntervals $ \a ->
    IntegerInterval.empty * a == IntegerInterval.empty

prop_mult_zero =
  forAll integerIntervals $ \a ->
    not (IntegerInterval.null a) ==> IntegerInterval.singleton 0 * a ==  IntegerInterval.singleton 0

prop_mult_member =
  forAll integerIntervals $ \a ->
  forAll integerIntervals $ \b ->
    and [ (x*y) `IntegerInterval.member` (a*b)
        | x <- maybeToList $ IntegerInterval.pickup a
        , y <- maybeToList $ IntegerInterval.pickup b
        ]

case_mult_test1 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = 1 <=..<= 2
    ival2 = 1 <=..<= 2
    ival3 = 1 <=..<= 4

case_mult_test2 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = 1 <=..<= 2
    ival2 = 1 <..< 2
    ival3 = IntegerInterval.empty -- *

case_mult_test3 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = 1 <..< 2
    ival2 = 1 <..< 2
    ival3 = IntegerInterval.empty -- *

case_mult_test4 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = 2 <..< PosInf
    ival2 = 3 <..< PosInf
    ival3 = 11 <..< PosInf -- *

case_mult_test5 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = NegInf <..< (-3)
    ival2 = NegInf <..< (-2)
    ival3 = 11 <..< PosInf -- *

case_mult_test6 = ival1 * ival2 @?= ival3
  where
    ival1 :: IntegerInterval
    ival1 = 2 <..< PosInf
    ival2 = NegInf <..< (-2)
    ival3 = NegInf <..< (-8) -- *

{--------------------------------------------------------------------
  Read
--------------------------------------------------------------------}

prop_show_read_invariance =
  forAll integerIntervals $ \i -> do
    i == read (show i)

{--------------------------------------------------------------------
  Conversion between Interval and IntegerInterval
--------------------------------------------------------------------}

prop_fromInterval_toInterval =
  forAll integerIntervals $ \i ->
    IntegerInterval.fromInterval (IntegerInterval.toInterval i) == i

prop_fromIntervalOver_toInterval =
  forAll integerIntervals $ \i ->
    IntegerInterval.fromIntervalOver (IntegerInterval.toInterval i :: Interval Rational) == i

prop_fromIntervalUnder_toInterval =
  forAll integerIntervals $ \i ->
    IntegerInterval.fromIntervalUnder (IntegerInterval.toInterval i :: Interval Rational) == i

prop_fromIntervalOver_toInterval_adjoint =
  forAll intervals $ \a ->
    forAll integerIntervals $ \b ->
      IntegerInterval.fromIntervalOver a `IntegerInterval.isSubsetOf` b
      == a `Interval.isSubsetOf` IntegerInterval.toInterval b

prop_toInterval_fromIntervalUnder_adjoint =
  forAll integerIntervals $ \a ->
    forAll intervals $ \b ->
      IntegerInterval.toInterval a `Interval.isSubsetOf` b
      == a `IntegerInterval.isSubsetOf` IntegerInterval.fromIntervalUnder b

prop_toInterval_fromInterval =
  forAll arbitrary $ \(i :: Interval Integer) ->
    IntegerInterval.toInterval (IntegerInterval.fromInterval i) `Interval.isSubsetOf` i

{--------------------------------------------------------------------
  Generators
--------------------------------------------------------------------}

instance Arbitrary r => Arbitrary (Extended r) where
  arbitrary =
    oneof
    [ return NegInf
    , return PosInf
    , liftM Finite arbitrary
    ]

instance (Arbitrary r, Ord r) => Arbitrary (Interval.Interval r) where
  arbitrary = do
    lb <- arbitrary
    ub <- arbitrary
    return $ Interval.interval lb ub

instance Arbitrary IntegerInterval where
  arbitrary = do
    lb <- arbitrary
    ub <- arbitrary
    return $ IntegerInterval.interval lb ub

integerIntervals :: Gen IntegerInterval
integerIntervals = arbitrary

intervals :: Gen (Interval.Interval Rational)
intervals = arbitrary

pos :: IntegerInterval
pos = 0 <..< PosInf

neg :: IntegerInterval
neg = NegInf <..< 0

nonpos :: IntegerInterval
nonpos = NegInf <..<= 0

nonneg :: IntegerInterval
nonneg = 0 <=..< PosInf

------------------------------------------------------------------------
-- Test harness

main :: IO ()
main = $(defaultMainGenerator)