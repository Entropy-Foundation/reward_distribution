export function buildLevels(leaves) {
  if (leaves.length === 0) throw new Error('no leaves')
  const levels = [leaves.slice()] // level 0

  while (levels[levels.length - 1].length > 1) {
    const cur = levels[levels.length - 1]
    const next = []

    for (let i = 0; i < cur.length; i += 2) {
      const a = cur[i]
      const b = i + 1 < cur.length ? cur[i + 1] : cur[i]
      const leftRight =
        Buffer.compare(a, b) <= 0
          ? Buffer.concat([a, b])
          : Buffer.concat([b, a])
      next.push(keccak(leftRight))
    }

    levels.push(next)
  }
  return levels
}

export function buildProof(levels, leafIndex) {
  const proof = []
  let idx = leafIndex
  for (let h = 0; h < levels.length - 1; h++) {
    const cur = levels[h]
    const sibIdx =
      idx % 2 === 0 ? (idx + 1 < cur.length ? idx + 1 : idx) : idx - 1
    proof.push(cur[sibIdx])
    idx = Math.floor(idx / 2)
  }
  return proof
}
