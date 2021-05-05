{-# language FlexibleContexts #-}
{-# language FlexibleInstances #-}
{-# language MultiParamTypeClasses #-}
{-# language NamedFieldPuns #-}
{-# language ScopedTypeVariables #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}

module Rel8.Table.List
  ( ListTable(..)
  , listTable, insertListTable, nameListTable
  )
where

-- base
import Data.Functor.Identity ( Identity( Identity ) )
import Data.Kind ( Type )
import Data.Type.Equality ( (:~:)( Refl ) )
import Prelude

-- rel8
import Rel8.Expr ( Expr, Col(..) )
import Rel8.Expr.Array ( sappend, sempty, slistOf )
import Rel8.Kind.Necessity ( SNecessity( SOptional, SRequired ) )
import Rel8.Schema.Dict ( Dict( Dict ) )
import Rel8.Schema.HTable.List ( HListTable )
import Rel8.Schema.HTable.Vectorize ( happend, hempty, hvectorize )
import Rel8.Schema.Insert ( Col( OptionalInsert, RequiredInsert ), Insert )
import Rel8.Schema.Name ( Col( NameCol ), Name )
import Rel8.Schema.Null ( Nullity( Null, NotNull ) )
import Rel8.Schema.Spec ( SSpec(..) )
import Rel8.Schema.Spec.ConstrainDBType ( dbTypeDict, dbTypeNullity )
import Rel8.Schema.Reify ( hreify, hunreify )
import Rel8.Table
  ( Table, Context, Columns, fromColumns, toColumns
  , reify, unreify
  )
import Rel8.Table.Alternative
  ( AltTable, (<|>:)
  , AlternativeTable, emptyTable
  )
import Rel8.Table.Eq ( EqTable, eqTable )
import Rel8.Table.Ord ( OrdTable, ordTable )
import Rel8.Table.Recontextualize ( Recontextualize )
import Rel8.Table.Serialize ( FromExprs, ToExprs, fromResult, toResult )
import Rel8.Table.Unreify ( Unreifiable )


-- | A @ListTable@ value contains zero or more instances of @a@. You construct
-- @ListTable@s with 'Rel8.many' or 'Rel8.listAgg'.
type ListTable :: Type -> Type
newtype ListTable a = ListTable (HListTable (Columns a) (Col (Context a)))


instance (Table context a, Unreifiable context a) =>
  Table context (ListTable a)
 where
  type Columns (ListTable a) = HListTable (Columns a)
  type Context (ListTable a) = Context a

  fromColumns = ListTable
  toColumns (ListTable a) = a

  reify Refl (ListTable a) = ListTable (hreify a)
  unreify Refl (ListTable a) = ListTable (hunreify a)


instance
  ( Unreifiable from a, Unreifiable to b
  , Recontextualize from to a b
  )
  => Recontextualize from to (ListTable a) (ListTable b)


instance EqTable a => EqTable (ListTable a) where
  eqTable =
    hvectorize
      (\SSpec {} (Identity dict) -> case dbTypeDict dict of
          Dict -> case dbTypeNullity dict of
            Null -> Dict
            NotNull -> Dict)
      (Identity (eqTable @a))


instance OrdTable a => OrdTable (ListTable a) where
  ordTable =
    hvectorize
      (\SSpec {} (Identity dict) -> case dbTypeDict dict of
          Dict -> case dbTypeNullity dict of
            Null -> Dict
            NotNull -> Dict)
      (Identity (ordTable @a))


type instance FromExprs (ListTable a) = [FromExprs a]


instance ToExprs exprs a => ToExprs (ListTable exprs) [a] where
  fromResult = fmap (fromResult @exprs) . fromColumns
  toResult = toColumns . fmap (toResult @exprs)


instance AltTable ListTable where
  (<|>:) = (<>)


instance AlternativeTable ListTable where
  emptyTable = mempty


instance Table Expr a => Semigroup (ListTable a) where
  ListTable as <> ListTable bs = ListTable $
    happend (\_ _ (DB a) (DB b) -> DB (sappend a b)) as bs


instance Table Expr a => Monoid (ListTable a) where
  mempty = ListTable $ hempty $ \nullability info ->
    DB (sempty nullability info)


listTable :: Table Expr a => [a] -> ListTable a
listTable =
  ListTable .
  hvectorize (\SSpec {info} -> DB . slistOf info . fmap unDB) .
  fmap toColumns


insertListTable :: Table Insert a => [a] -> ListTable a
insertListTable =
  ListTable .
  hvectorize (\SSpec {necessity, info} -> case necessity of
    SRequired -> RequiredInsert . slistOf info . fmap (\(RequiredInsert a) -> a)
    SOptional -> OptionalInsert . fmap (slistOf info) . traverse (\(OptionalInsert a) -> a)) .
  fmap toColumns


nameListTable :: Table Name a => a -> ListTable a
nameListTable =
  ListTable .
  hvectorize (\_ (Identity (NameCol a)) -> NameCol a) .
  pure .
  toColumns
