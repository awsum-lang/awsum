-- | Parallel-copy scheduling for in-place 'CReuse' stores on the managed
-- backends (JS/JVM/CLR — LLVM and WASM pre-read every binder through their
-- refcount discipline and need no schedule).
--
-- An in-place rebuild reads the dying cell's old slots while overwriting
-- them: in a CPS K-arm the new slot 2 is the old slot 1, the new slot 3 the
-- old slot 2. With stores emitted in slot order those reads would see the
-- new values, which is why the arm binders stayed extracted — every old
-- value parked in a local before the first store. But the store order is
-- the emitter's to choose: ordering each slot's store after every read of
-- its old value turns the acyclic part into direct cell-to-cell moves
-- (@cell[3] = cell[2]; cell[2] = cell[1]; cell[1] = k@ — no locals at all),
-- and only a genuine permutation cycle (a field swap) keeps one extracted
-- binder as its temp. The same dependency discipline as the JS
-- 'CContinue' parallel rebind.
--
-- The schedule is consulted for 'ReuseUnique' cells only: a guarded reuse
-- lowers on the managed backends as a fresh allocation, whose field reads
-- never race the stores.
module Awsum.Codegen.ReuseSchedule (ReuseStore (..), scheduleReuse, reuseSlotElided) where

import Awsum.Core
import Awsum.Syntax (Name)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Relude

-- | One planned store into the reused cell, in emission order. Slots are
--   1-based (slot 0 is the tag, written separately — never read as a
--   value, so its store needs no place in the order).
data ReuseStore
  = -- | @cell[dst] := cell[src]@ — the old value read directly off the
    --   cell, no extracted binder involved.
    StoreFromSlot Int Int
  | -- | @cell[dst] := binder@ — the field names the arm binder of slot
    --   @src@, but the direct read would race another pending store: the
    --   extracted binder is the cycle's temp and must stay extracted.
    StoreFromBinder Int Name
  | -- | @cell[dst] := fields !! (dst - 1)@ — an unrelated expression (a
    --   binder of another cell, a fresh construction); the backend
    --   evaluates it as it always did. It cannot read this cell's slots:
    --   'Awsum.Reuse' never rewrites beside a projection of the target,
    --   and binder reads go through their extracted locals.
    StoreExtern Int
  deriving stock (Show, Eq)

-- | Order the slot stores of @CReuse _ n tag fields@ so every old slot is
--   read before it is overwritten. @armVars@ are the matched arm's
--   binders, positionally naming the old slots. Returns the stores (a
--   self-move — @fields !! (i-1)@ naming the binder of slot @i@ — emits
--   nothing) and the binders the schedule still reads as extracted locals
--   (the cycle breakers). A binder /not/ in that set and not otherwise
--   used in the arm body needs no extraction at all.
scheduleReuse :: [Name] -> [CExpr] -> ([ReuseStore], Set Name)
scheduleReuse armVars fields = go pending0 [] Set.empty
  where
    slotOfBinder = Map.fromList (zip armVars [1 :: Int ..])
    classify (dst, f) = case f of
      CVar v
        | Just src <- Map.lookup v slotOfBinder ->
            if src == dst
              then Nothing -- self-move: the slot already holds the value
              else Just (PMove dst src v)
      _ -> Just (PExtern dst)
    pending0 = mapMaybe classify (zip [1 ..] fields)

    -- Only an unbroken move still *reads* a slot; a breaker reads its
    -- extracted binder and an extern reads no slot of this cell.
    srcsOf ps = Set.fromList [src | PMove _ src _ <- ps]

    go [] acc breakers = (reverse acc, breakers)
    go pending acc breakers =
      let pendingSrcs = srcsOf pending
          ready = [p | p <- pending, dstOf p `Set.notMember` pendingSrcs]
       in case ready of
            [] ->
              -- Every remaining move's destination is still read by some
              -- other move: a permutation cycle. Break it at the first
              -- edge — route that one read through the extracted binder.
              -- The edge is *reclassified*, not emitted: its read no
              -- longer pins its source slot, but its own store must still
              -- wait until everything reading its destination has run
              -- (emitting it immediately would clobber the slot the rest
              -- of the cycle is about to read).
              case pending of
                PMove dst _ v : rest ->
                  go (PBreaker dst v : rest) acc (Set.insert v breakers)
                -- Unreachable: at a stall every pending dst is some move's
                -- src; dsts are distinct and only unbroken moves contribute
                -- srcs, so by pigeonhole every stalled item is a move.
                -- Emitting a breaker or extern whose dst is still read
                -- would clobber a slot the rest of the cycle is about to
                -- read — fail loudly rather than corrupt the schedule.
                _ -> error "ReuseSchedule: stalled schedule head is not an unbroken move (scheduler invariant broken)"
            _ ->
              let readySet = Set.fromList (map dstOf ready)
                  rest = [p | p <- pending, dstOf p `Set.notMember` readySet]
                  emitted = map emit ready
               in go rest (reverse emitted <> acc) breakers
    dstOf = \case
      PMove dst _ _ -> dst
      PBreaker dst _ -> dst
      PExtern dst -> dst
    emit = \case
      PMove dst src _ -> StoreFromSlot dst src
      PBreaker dst v -> StoreFromBinder dst v
      PExtern dst -> StoreExtern dst

-- | A not-yet-emitted slot store: an unbroken move (reads @src@), a
--   broken cycle edge (reads its extracted binder), an unrelated field.
data Pending
  = PMove Int Int Name
  | PBreaker Int Name
  | PExtern Int

-- | Binders of one arm whose every use in the body is read off the cell
--   by the 'CReuse' store schedule — their extraction would bind a local
--   nothing reads. A use is scheduled away exactly when it is a slot-move
--   field of a 'ReuseUnique' reuse of this same scrutinee: a self-move
--   stores nothing, a slot-move reads the old slot directly, while a
--   cycle breaker reads the extracted binder and every other position —
--   externs, fields of other cells' reuses, a reuse /target/ name, plain
--   reads — keeps the local alive.
--
--   @externOk@ is the backend's gate on the node's extern fields: an
--   emitter that cannot evaluate some field inline with the cell parked
--   (a multi-arm case on the JVM/CLR operand stack) falls back to the
--   unscheduled path for the whole node, which reads every binder — such
--   a node schedules nothing away. The JS emitter passes @const True@.
reuseSlotElided :: (CExpr -> Bool) -> Name -> [Name] -> CExpr -> Set Name
reuseSlotElided externOk scrut vars body =
  Set.fromList [v | v <- vars, binderUsedIn v body, nonScheduledUses v body == 0]
  where
    slotOf = Map.fromList (zip vars [1 :: Int ..])
    -- Will the backend take the scheduled path for this node? Move and
    -- self-move fields (a 'CVar' naming one of the arm binders) need no
    -- gate; every other field must pass the backend's inline-evaluation
    -- test.
    nodeScheduled flds =
      and
        [ externOk f
        | f <- flds,
          case f of
            CVar w -> not (Map.member w slotOf)
            _ -> True
        ]
    nonScheduledUses :: Name -> CExpr -> Int
    nonScheduledUses v = goN
      where
        goN = \case
          CVar w -> if w == v then 1 else 0
          CReuse ReuseUnique s _ flds
            | s == scrut,
              nodeScheduled flds ->
                let (_, breakers) = scheduleReuse vars flds
                    inField (i, f) = case f of
                      CVar w
                        | w == v,
                          Just src <- Map.lookup w slotOf ->
                            if Set.member w breakers && src /= i then 1 else 0
                      _ -> goN f
                 in sum (zipWith (curry inField) [1 :: Int ..] flds)
          CReuse _ s _ flds -> (if s == v then 1 else 0) + sum (map goN flds)
          CProj w _ -> if w == v then 1 else 0
          CCall f xs -> goN f + sum (map goN xs)
          CCon _ fs -> sum (map goN fs)
          CRow _ x -> goN x
          CCase s alts -> goN s + sum [goN b | (_, _, b) <- alts]
          CRowCase s alts -> goN s + sum [goN b | (_, _, b) <- alts]
          CLoop b -> goN b
          CContinue xs -> sum (map goN xs)
          CDrop _ b -> goN b
          CLet _ rhs b -> goN rhs + goN b
          CJoin _ _ jb inner -> goN jb + goN inner
          CJump _ args -> sum (map goN args)
          CString _ -> 0
          CIntLit _ _ -> 0
          CBuiltIn _ -> 0
