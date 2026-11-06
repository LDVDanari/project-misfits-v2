// Shared by the server (Tebex prices) and the browser (cart totals).
// USD shows as "$12.50"; any other dollar currency gets its code so nobody mixes them up ("$17 CAD").
export function formatPrice(amount, currency = 'USD') {
  const n = Number(amount);
  if (!Number.isFinite(n)) return null;
  const code = String(currency || 'USD').toUpperCase();
  try {
    const text = new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code,
      currencyDisplay: 'narrowSymbol',
      minimumFractionDigits: Number.isInteger(n) ? 0 : 2
    }).format(n);
    return code === 'USD' ? text : `${text} ${code}`;
  } catch {
    return '$' + n.toFixed(Number.isInteger(n) ? 0 : 2) + (code === 'USD' ? '' : ' ' + code);
  }
}

// "$17.50 CAD" -> 17.5
export function priceNumber(text) {
  const n = Number(String(text ?? '').replace(/[^0-9.]/g, ''));
  return Number.isFinite(n) ? n : 0;
}
