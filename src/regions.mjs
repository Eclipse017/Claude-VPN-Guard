// Country-level network gate, not a determination of a person's service eligibility.
// Source reviewed 2026-10-25: official Claude Help Center, article updated 2026-03-16.
export const REGION_SOURCE='https://support.claude.com/en/articles/8461763-where-can-i-access-claude';
export const REGION_REVIEWED='2026-10-25';
export const REGION_EXPIRES='2027-01-23T00:00:00Z';
// Ambiguous/subregional entries (including Ukraine and Mariana Islands) are deliberately
// excluded because the neutral probe returns only a country code.
export const REGION_CODES=new Set('AL DZ AD AO AG AR AM AU AT AZ BS BH BD BB BE BZ BJ BT BO BA BW BR BN BG BF BI KH CM CA CV TD CL CO KM CG CR HR CZ DK DJ DM DO TL EC EG SV GQ EE SZ FJ FI FR GA GM GE DE GH GR GD GT GN GW GY HT HN HU IS IN ID IQ IE IL IT CI JM JP JO KZ KE KI KW KG LA LV LB LS LR LI LT LU MG MW MY MV MT MH MR MU MX FM MD MC MN ME MA MZ NA NR NP NL NZ NE NG MK NO OM PK PW PS PA PG PY PE PH PL PT QA CY RO RW KN LC VC WS SM ST SA SN RS SC SL SG SK SI SB ZA KR ES LK SR SE CH TW TJ TZ TH TG TO TT TN TR TM TV UG AE GB US UY UZ VU VA VN ZM ZW'.split(' '));
export function regionAllowed(code,now=Date.now()){
 return typeof code==='string'&&REGION_CODES.has(code)&&Number.isFinite(now)&&now>=Date.parse(REGION_REVIEWED)&&now<Date.parse(REGION_EXPIRES);
}
