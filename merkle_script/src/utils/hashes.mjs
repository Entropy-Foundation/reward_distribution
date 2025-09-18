import pkg from 'js-sha3'
import crypto from 'crypto'

const { keccak_256 } = pkg

export function bcsAddress(addr) {
  if (typeof addr !== 'string') throw new Error('address must be a string')
  let hex = addr.startsWith('0x') ? addr.slice(2) : addr
  if (!/^[0-9a-fA-F]*$/.test(hex)) throw new Error(`invalid hex: ${addr}`)
  if (hex.length > 64) throw new Error(`address too long (>32 bytes): ${addr}`)
  if (hex.length % 2 === 1) hex = '0' + hex
  hex = hex.padStart(64, '0')
  return Buffer.from(hex, 'hex')
}

export function bcsU64(n) {
  if (!Number.isInteger(n) || n < 0)
    throw new Error(
      `cumulative_amount must be integer (8-dec scaled). got: ${n}`
    )
  let x = BigInt(n)
  const buf = Buffer.alloc(8)
  for (let i = 0; i < 8; i++) {
    buf[i] = Number(x & 0xffn)
    x >>= 8n
  }
  return buf
}

// ---------- Hashes ----------
export const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest()
export function keccak(buf) {
  const hex = keccak_256(buf)
  return Buffer.from(hex, 'hex')
}

export function hashLeaf(address, cumulative_amount) {
  const payload = Buffer.concat([
    bcsAddress(address),
    bcsU64(cumulative_amount),
  ])
  return sha256(payload)
}
