# CAP Payment Scheme → Pillar 1 / Pillar 2 Mapping

Used by `codes/Econ_calc.R` to derive the AgMIP template variables `BUDG_1stP`
and `BUDG_2ndP` from the CAP payment-scheme codes reported under
`VAR_ID == "BUDG"` in the `OUTPUT` GDX symbol (as opposed to the
commodity-linked `BUDG` rows, which already drive the existing `BUDG`
variable via crop/livestock subsidies).

Classification is based on standard EU CAP terminology (2014-2022 CAP and the
2023+ CAP Strategic Plan reform). Confidence is noted per code since the raw
codes are abbreviations, not documented anywhere in this repo or the GDX
itself (no pillar-mapping set exists in the GDX; checked via `gamstransfer`).

**Structural limitation:** these scheme codes are not linked to a specific
commodity in the GDX, so `BUDG_1stP`/`BUDG_2ndP` are reported only at the
`Total` item level in the output — the `All crops`/`Livestock` item split
that the template shows for `BUDG` is not populated for these two variables.

## 1st Pillar — Direct Payments (EAGF, fully EU-funded)

| Code | Reasoning | Confidence |
|---|---|---|
| `dp_bps` | Basic Payment Scheme | High |
| `DPSAPS` | Single Area Payment Scheme | High |
| `DPBPS_SAPS` | Combined BPS/SAPS | High |
| `DPAGG_biss` | Basic Income Support for Sustainability (new CAP successor to BPS/SAPS) | High |
| `DPGREEN` | Greening payment (old CAP) | High |
| `DPYOUNG` | Young farmer payment (old CAP) | High |
| `DPAGG_cisyf` | Complementary Income Support for Young Farmers (new CAP) | High |
| `dpVcs` | Voluntary Coupled Support (old CAP) | High |
| `DPAGG_cispr` | Coupled Income Support (new CAP) | High |
| `DPAGG_cotto` | Cotton-specific coupled support | High |
| `DPCSCS` | Crop-Specific Coupled Support | Medium |
| `DP68` | Article 68 coupled support (pre-2013 CAP) | Medium |
| `DPAGG_criss` | Complementary Redistributive Income Support for Sustainability (new CAP) | High |
| `DPFIRHA` | Redistributive "first hectares" payment (old CAP) | Medium |
| `DPREG` | Regionalised flat-rate payment | Medium |
| `DPAGG_ecos` | Eco-scheme — environmentally themed but legally Pillar 1 under the 2023 reform | High |
| `DPNAT` | National reserve/envelope top-up to direct payments | Medium |
| `DPFRMF` | Unclear — assumed a farm-level direct-payment variant | **Low** |
| `DPFRMS` | Unclear — assumed a farm-level direct-payment variant | **Low** |

## 2nd Pillar — Rural Development (EAFRD, co-financed nationally)

| Code | Reasoning | Confidence |
|---|---|---|
| `DPRD_LFA` | Rural Development: Less Favoured Areas | High |
| `DPRD_N2K` | Rural Development: Natura 2000 | High |
| `DPRD_SeExte` | Rural Development: extensification-type measure | Medium |
| `DPAE` | Agri-environmental payment (AECM) — flagship Pillar 2 instrument | High |
| `DPAGG_envc` | Environmental commitment — same AECM family as `DPAE` | Medium |
| `DPAGG_ANC7` | Areas of Natural Constraint (Art. 71) — same family as LFA, newer term | High |
| `DPNATCO` | National co-financing — structurally only exists for EAFRD-funded (Pillar 2) measures, since Pillar 1 is 100% EU-funded with no co-financing | High |

## Review history

- 2026-08-11: Initial mapping proposed and approved for implementation. Two
  `Low`-confidence codes (`DPFRMF`, `DPFRMS`) flagged for follow-up if their
  true meaning becomes known.
