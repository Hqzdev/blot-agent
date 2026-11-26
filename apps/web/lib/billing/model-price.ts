// Pilot accounting defaults to $1 per million tokens. Contracted provider prices override the pilot rate.
export function modelPrice(input: number, output: number) {
  const incoming = Number(process.env.BLOT_INPUT_MICROUSD_PER_MTOK ?? 1000000);
  const outgoing = Number(process.env.BLOT_OUTPUT_MICROUSD_PER_MTOK ?? 1000000);
  if (![incoming, outgoing].every((n) => Number.isSafeInteger(n) && n > 0))
    throw new Error('Managed model metering prices are unavailable');
  return Math.ceil((input * incoming + output * outgoing) / 1000000);
}
