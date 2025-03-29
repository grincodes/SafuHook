import {
  PoolFrozen as PoolFrozenEvent,
  PoolUnfrozen as PoolUnfrozenEvent,
} from "../generated/SafuHook/SafuHook";
import { Pool } from "../generated/schema";

export function handlePoolFrozen(event: PoolFrozenEvent): void {
  let id = event.params.poolId.toHex();
  let pool = Pool.load(id);

  if (!pool) {
    pool = new Pool(id);
  }

  pool.frozen = true;
  pool.lastAction = event.block.timestamp;
  pool.save();
}

export function handlePoolUnfrozen(event: PoolUnfrozenEvent): void {
  let id = event.params.poolId.toHex();
  let pool = Pool.load(id);

  if (!pool) {
    pool = new Pool(id);
  }

  pool.frozen = false;
  pool.lastAction = event.block.timestamp;
  pool.save();
}
