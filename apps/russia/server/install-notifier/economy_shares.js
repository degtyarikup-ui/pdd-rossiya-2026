// Split whole cents by largest remainder so the displayed amounts add up to the profit.
export function splitProfit(shares, profit) {
  const cents = Math.max(0, Math.round(profit * 100));
  const whole = Math.floor(cents / 10000);
  const portions = shares.map(({ percent }) => {
    const basisPoints = Math.round(percent * 100);
    const weighted = (cents % 10000) * basisPoints;
    return { cents: whole * basisPoints + Math.floor(weighted / 10000), remainder: weighted % 10000 };
  });
  const unassigned = cents - portions.reduce((sum, part) => sum + part.cents, 0);
  const ranked = [...portions].sort((a, b) => b.remainder - a.remainder);
  for (const part of ranked.slice(0, unassigned)) part.cents++;
  return portions.map(part => part.cents / 100);
}

const round = value => Math.round((value + Number.EPSILON) * 100) / 100;

export function profitAllocation(config, profit) {
  if (config.profitShares) {
    const payouts = splitProfit(config.profitShares, profit);
    return {
      shares: config.profitShares.map((share, i) => ({ ...share, amount: payouts[i] })),
      reinvest: 0, distributable: profit, partners: {},
    };
  }
  // Preserve the previous accounting until the first save from the new editor.
  const { reinvestPercent, nikitaSharePercent, sergeySharePercent } = config;
  const reinvest = round(Math.max(0, profit) * reinvestPercent / 100);
  const distributable = round(profit - reinvest);
  const payout = Math.max(0, distributable);
  const nikita = round(payout * nikitaSharePercent / 100);
  const sergey = round(payout - nikita);
  const fundPercent = round(reinvestPercent);
  const nikitaTotalPercent = round((100 - fundPercent) * nikitaSharePercent / 100);
  const shares = [
    { name: 'В развитие', percent: fundPercent, amount: reinvest },
    { name: 'Сергей', percent: round(100 - fundPercent - nikitaTotalPercent), amount: sergey },
    { name: 'Никита', percent: nikitaTotalPercent, amount: nikita },
  ];
  return { shares, reinvest, distributable, partners: {
    sergey: { name: shares[1].name, role: 'Основатель / Разработка', percent: sergeySharePercent, amount: sergey },
    nikita: { name: shares[2].name, role: 'Партнёр / Развитие', percent: nikitaSharePercent, amount: nikita },
  } };
}
