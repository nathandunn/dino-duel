#!/bin/bash
# tools/stats.sh A B [N] [PA] [PB] - one pairing, digested
godot --headless --path . -s tools/sim.gd -- --sim=${3:-20} --a=$1 --b=$2 --pa=${4:-Balanced} --pb=${5:-Balanced} 2>&1 | grep SUMMARY | python3 -c "
import json,sys; d=json.loads(sys.stdin.read()[8:]); n=d['n']
print(d['species'], d['wins'], 'draws',d['draws'], 'avg %.0fs'%d['avg_t'], d['how'])
for s in d['side']: print(' ', {k:'%d/%d hit %d miss %d dodged dmg %.1f'%(v['tries'],v['hits'],v['missed'],v['dodged'],v['dmg']) for k,v in s['weapons'].items() if v['tries']}, '| dodges',s['dodges'], 'holds',s['holds'],'latch',s['latches'],'charges',s['charges'],'roars',s['roars'],'kd',s['kd_dealt'],'| blood end %.2f'%(s['blood_end']/n),'exh %.1fs'%(s['exhausted_s']/n), '| taken', {k:round(v/n,2) for k,v in sorted(s['taken'].items(), key=lambda x:-x[1])}, s['causes'], 'fled',s['fled'])"
