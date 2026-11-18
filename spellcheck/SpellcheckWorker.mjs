import dictionaryPart1 from './DictionaryPart1.mjs'
import dictionaryPart2 from './DictionaryPart2.mjs'
var JOTPIN_NSPELL_BUNDLE = "\"use strict\";var JotPinNSpell=(()=>{var g=(e,r)=>()=>{try{return r||e((r={exports:{}}).exports,r),r.exports}catch(i){throw r=0,i}};var $=g((Lr,H)=>{H.exports=function(r){return r!=null&&r.constructor!=null&&typeof r.constructor.isBuffer==\"function\"&&r.constructor.isBuffer(r)}});var K=g((Ir,J)=>{\"use strict\";J.exports=_e;var ke=[];function _e(e,r){var i=0,t;if(!r)return ke;if(e.FLAG===\"long\"){for(t=new Array(Math.ceil(r.length/2));i<r.length;)t[i/2]=r.slice(i,i+2),i+=2;return t}return r.split(e.FLAG===\"num\"?\",\":\"\")}});var ee=g((Ur,Z)=>{\"use strict\";var Ve=K();Z.exports=Je;var He=[].push,M=\"etaoinshrdlcumwfgypbvkjxqz\".split(\"\"),I=/\\s+/,$e=[\"qwertzuop\",\"yxcvbnm\",\"qaw\",\"say\",\"wse\",\"dsx\",\"sy\",\"edr\",\"fdc\",\"dx\",\"rft\",\"gfv\",\"fc\",\"tgz\",\"hgb\",\"gv\",\"zhu\",\"jhn\",\"hb\",\"uji\",\"kjm\",\"jn\",\"iko\",\"lkm\"];function Je(e){var r=Object.create(null),i=Object.create(null),t=Object.create(null),n=[],o={in:[],out:[]},s=[],h=e.toString(\"utf8\"),f=[],c=0,a=h.indexOf(`\n`),l,R,u,d,O,E,x,m,q,v,N,p,A;for(t.KEY=[];a>-1;)C(h.slice(c,a)),c=a+1,a=h.indexOf(`\n`,c);for(C(h.slice(c)),a=-1;++a<f.length;)if(R=f[a],l=R.split(I),u=l[0],u===\"REP\"){for(d=a+parseInt(l[1],10);++a<=d;)l=f[a].split(I),n.push([l[1],l[2]]);a--}else if(u===\"ICONV\"||u===\"OCONV\"){for(d=a+parseInt(l[1],10),m=o[u===\"ICONV\"?\"in\":\"out\"];++a<=d;)l=f[a].split(I),m.push([new RegExp(l[1],\"g\"),l[2]]);a--}else if(u===\"COMPOUNDRULE\"){for(d=a+parseInt(l[1],10);++a<=d;)for(v=f[a].split(I)[1],q=-1,s.push(v);++q<v.length;)i[v.charAt(q)]=[];a--}else if(u===\"PFX\"||u===\"SFX\"){for(d=a+parseInt(l[3],10),v={type:u,combineable:l[2]===\"Y\",entries:[]},r[l[1]]=v;++a<=d;){l=f[a].split(I),O=l[2],E=l[3].split(\"/\"),x=l[4],m={add:\"\",remove:\"\",match:\"\",continuation:Ve(t,E[1])},E&&E[0]!==\"0\"&&(m.add=E[0]);try{O!==\"0\"&&(m.remove=u===\"SFX\"?Q(O):O),x&&x!==\".\"&&(m.match=u===\"SFX\"?Q(x):Qe(x))}catch(w){m=null}m&&v.entries.push(m)}a--}else if(u===\"TRY\"){for(x=l[1],p=-1,N=[];++p<x.length;)A=x.charAt(p),A.toLowerCase()===A&&N.push(A);for(p=-1;++p<M.length;)x.indexOf(M[p])<0&&N.push(M[p]);t[u]=N}else u===\"KEY\"?He.apply(t[u],l[1].split(\"|\")):u===\"COMPOUNDMIN\"?t[u]=Number(l[1]):u===\"ONLYINCOMPOUND\"?(t[u]=l[1],i[l[1]]=[]):t[u]=l[1];return isNaN(t.COMPOUNDMIN)&&(t.COMPOUNDMIN=3),t.KEY.length||(t.KEY=$e),t.TRY||(t.TRY=M.concat()),t.KEEPCASE||(t.KEEPCASE=!1),{compoundRuleCodes:i,replacementTable:n,conversion:o,compoundRules:s,rules:r,flags:t};function C(w){w=w.trim(),w&&w.charCodeAt(0)!==35&&f.push(w)}}function Q(e){return new RegExp(e+\"$\")}function Qe(e){return new RegExp(\"^\"+e)}});var z=g((Fr,re)=>{\"use strict\";re.exports=Ze;function Ze(e,r){for(var i=-1;++i<r.length;)e=e.replace(r[i][0],r[i][1]);return e}});var U=g((Mr,te)=>{\"use strict\";te.exports=er;function er(e,r,i){return i&&r in e&&i.indexOf(e[r])>-1}});var ae=g((Br,ie)=>{\"use strict\";var rr=U();ie.exports=tr;function tr(e,r){var i=-1;if(e.data[r])return!rr(e.flags,\"ONLYINCOMPOUND\",e.data[r]);if(r.length>=e.flags.COMPOUNDMIN){for(;++i<e.compoundRules.length;)if(e.compoundRules[i].test(r))return!0}return!1}});var B=g((Pr,ne)=>{\"use strict\";var ir=z(),j=ae(),G=U();ne.exports=ar;function ar(e,r,i){var t=r.trim(),n;if(!t)return null;if(t=ir(t,e.conversion.in),j(e,t))return!i&&G(e.flags,\"FORBIDDENWORD\",e.data[t])?null:t;if(t.toUpperCase()===t){if(n=t.charAt(0)+t.slice(1).toLowerCase(),se(e.flags,e.data[n],i))return null;if(j(e,n))return n}if(n=t.toLowerCase(),n!==t){if(se(e.flags,e.data[n],i))return null;if(j(e,n))return n}return null}function se(e,r,i){return G(e,\"KEEPCASE\",r)||i||G(e,\"FORBIDDENWORD\",r)}});var oe=g((Tr,ue)=>{\"use strict\";var sr=B();ue.exports=nr;function nr(e){return!!sr(this,e)}});var ce=g((Yr,fe)=>{\"use strict\";fe.exports=ur;function ur(e){var r=le(e.charAt(0)),i=e.slice(1);return!i||(i=le(i),r===i)?r:r===\"u\"&&i===\"l\"?\"s\":null}function le(e){return e===e.toLowerCase()?\"l\":e===e.toUpperCase()?\"u\":null}});var de=g((Wr,ve)=>{\"use strict\";var P=ce(),he=z(),or=U(),lr=B();ve.exports=cr;var fr=[].push;function cr(e){var r=this,i={},t=[],n={},o,s,h=[],f,c,a,l,R,u,d,O,E,x,m,q,v,N,p,A,C,w,y,L,Y,W,F;if(e=he(e.trim(),r.conversion.in),!e||r.correct(e))return[];for(F=P(e),c=-1;++c<r.replacementTable.length;)for(s=r.replacementTable[c],a=e.indexOf(s[0]);a>-1;)h.push(e.replace(s[0],s[1])),a=e.indexOf(s[0],a+1);for(c=-1;++c<e.length;)for(O=e.charAt(c),x=e.slice(0,c),m=e.slice(c+1),v=O.toLowerCase(),q=v!==O,i={},a=-1;++a<r.flags.KEY.length;)if(E=r.flags.KEY[a],l=E.indexOf(v),!(l<0)){for(u=-1;++u<E.length;)if(u!==l){if(d=E.charAt(u),i[d])continue;i[d]=!0,q&&(d=d.toUpperCase()),h.push(x+d+m)}}for(c=-1,C=e.charAt(0),f=[\"\"],w=1,y=0;++c<e.length;){for(O=C,C=e.charAt(c+1),x=e.slice(0,c),s=O===C?\"\":O+O,a=-1,R=f.length;++a<R;)a<=w&&f.push(f[a]+s),f[a]+=O;++y<3&&(w=f.length)}for(fr.apply(h,f),f=[e],s=e.toLowerCase(),(e===s||F===null)&&f.push(e.charAt(0).toUpperCase()+s.slice(1)),s=e.toUpperCase(),e!==s&&f.push(s),o={state:{},weighted:n,suggestions:t},N=pe(r,o,f,h),p=0,w=Math.min(N.length,Math.pow(Math.max(15-e.length,3),3)),L=Math.max(Math.pow(10-e.length,3),1);!t.length&&p<w;)A=p+L,pe(r,o,N.slice(p,A)),p=A;for(t.sort(ze),f=[],Y=[],c=-1;++c<t.length;)W=he(t[c],r.conversion.out),s=W.toLowerCase(),Y.indexOf(s)<0&&(f.push(W),Y.push(s));return f;function ze(D,b){return je(D,b)||Ge(D,b)||Xe(D,b)}function je(D,b){return n[D]===n[b]?0:n[D]>n[b]?-1:1}function Ge(D,b){var _=P(D),V=P(b);return _===V?0:_===F?-1:V===F?1:void 0}function Xe(D,b){return D.localeCompare(b)}}function pe(e,r,i,t){var n=e.flags.TRY,o=e.data,s=e.flags,h=[],f=-1,c,a,l,R,u,d,O,E,x,m,q,v,N;if(t)for(;++f<t.length;)p(t[f],!0);for(f=-1;++f<i.length;)for(c=i[f],a=\"\",l=\"\",R=c.charAt(0),u=c,d=c.slice(1),O=R.toLowerCase()!==R,E=P(c),x=-1;++x<=c.length;)for(a+=l,m=u,u=d,d=u.slice(1),l=R,R=c.charAt(x+1),q=O,R&&(O=R.toLowerCase()!==R),u&&q!==O&&(p(a+A(u)),p(a+A(R)+A(l)+d)),p(a+u),u&&p(a+R+l+d),N=-1;++N<n.length;)v=n[N],q&&v!==v.toUpperCase()?(E!==\"s\"&&(p(a+v+m),p(a+v+u)),v=v.toUpperCase(),p(a+v+m),p(a+v+u)):(p(a+v+m),p(a+v+u));return h;function p(C,w){var y=r.state[C],L;y!==!!y&&(h.push(C),L=lr(e,C),y=L&&!or(s,\"NOSUGGEST\",o[L]),r.state[C]=y,y&&(r.weighted[C]=w?10:0,r.suggestions.push(C))),y&&r.weighted[C]++}function A(C){var w=C.charAt(0);return(w.toLowerCase()===w?w.toUpperCase():w.toLowerCase())+C.slice(1)}}});var Oe=g((Kr,we)=>{\"use strict\";var hr=B(),ge=U();we.exports=pr;function pr(e){var r=this,i=hr(r,e,!0);return{correct:r.correct(e),forbidden:!!(i&&ge(r.flags,\"FORBIDDENWORD\",r.data[i])),warn:!!(i&&ge(r.flags,\"WARN\",r.data[i]))}}});var me=g((zr,xe)=>{\"use strict\";xe.exports=Ce;function Ce(e,r,i,t){for(var n=-1,o,s,h,f,c;++n<r.entries.length;)if(o=r.entries[n],f=o.continuation,c=-1,(!o.match||o.match.test(e))&&(s=o.remove?e.replace(o.remove,\"\"):e,s=r.type===\"SFX\"?s+o.add:o.add+s,t.push(s),f&&f.length))for(;++c<f.length;)h=i[f[c]],h&&Ce(s,h,i,t);return t}});var k=g((jr,Ee)=>{\"use strict\";var Re=me();Ee.exports=gr;var vr=[].push,X=[];function dr(e,r,i){var t=e[r];r in e?t===X?e[r]=i.concat():vr.apply(t,i):e[r]=i.concat()}function gr(e,r,i,t){var n=-1,o,s,h,f,c,a,l;for((!(\"NEEDAFFIX\"in t.flags)||i.indexOf(t.flags.NEEDAFFIX)<0)&&dr(e,r,i);++n<i.length;)if(o=t.rules[i[n]],i[n]in t.compoundRuleCodes&&t.compoundRuleCodes[i[n]].push(r),o){for(a=Re(r,o,t.rules,[]),s=-1;++s<a.length;)if(a[s]in e||(e[a[s]]=X),o.combineable){for(h=n;++h<i.length;)if(c=t.rules[i[h]],c&&c.combineable&&o.type!==c.type)for(l=Re(a[s],c,t.rules,[]),f=-1;++f<l.length;)l[f]in e||(e[l[f]]=X)}}}});var Ae=g((Gr,Ne)=>{\"use strict\";var wr=k();Ne.exports=Cr;var Or=[];function Cr(e,r){var i=this;return wr(i.data,e,i.data[r]||Or,i),i}});var De=g((Xr,qe)=>{\"use strict\";qe.exports=xr;function xr(e){var r=this;return delete r.data[e],r}});var ye=g((kr,be)=>{\"use strict\";be.exports=mr;function mr(){return this.flags.WORDCHARS||null}});var Ue=g((_r,Ie)=>{\"use strict\";var Rr=K(),Er=k();Ie.exports=Nr;var Se=/\\s/g;function Nr(e,r,i){for(var t=e.toString(\"utf8\"),n=t.indexOf(`\n`)+1,o=t.indexOf(`\n`,n);o>-1;)t.charCodeAt(n)!==9&&Le(t.slice(n,o),r,i),n=o+1,o=t.indexOf(`\n`,n);Le(t.slice(n),r,i)}function Le(e,r,i){for(var t=e.indexOf(\"/\"),n=e.indexOf(\"#\"),o=\"\",s,h;t>-1&&e.charCodeAt(t-1)===92;)e=e.slice(0,t-1)+e.slice(t),t=e.indexOf(\"/\",t);n>-1?t>-1&&t<n?(s=e.slice(0,t),Se.lastIndex=t+1,h=Se.exec(e),o=e.slice(t+1,h?h.index:void 0)):s=e.slice(0,n):t>-1?(s=e.slice(0,t),o=e.slice(t+1)):s=e,s=s.trim(),s&&Er(i,s,Rr(r.flags,o.trim()),r)}});var Me=g((Vr,Fe)=>{\"use strict\";var Ar=Ue();Fe.exports=qr;function qr(e){var r=this,i=-1,t,n,o,s;for(Ar(e,r,r.data);++i<r.compoundRules.length;){for(t=r.compoundRules[i],n=\"\",s=-1;++s<t.length;)o=t.charAt(s),n+=r.compoundRuleCodes[o].length?\"(?:\"+r.compoundRuleCodes[o].join(\"|\")+\")\":o;r.compoundRules[i]=new RegExp(n,\"i\")}return r}});var Pe=g((Hr,Be)=>{\"use strict\";Be.exports=Dr;function Dr(e){var r=this,i=e.toString(\"utf8\").split(`\n`),t=-1,n,o,s,h;for(r.flags.FORBIDDENWORD===void 0&&(r.flags.FORBIDDENWORD=!1),h=r.flags.FORBIDDENWORD;++t<i.length;)n=i[t].trim(),n&&(n=n.split(\"/\"),s=n[0],o=s.charAt(0)===\"*\",o&&(s=s.slice(1)),r.add(s,n[1]),o&&r.data[s].push(h));return r}});var We=g(($r,Ye)=>{\"use strict\";var Te=$(),br=ee();Ye.exports=T;var S=T.prototype;S.correct=oe();S.suggest=de();S.spell=Oe();S.add=Ae();S.remove=De();S.wordCharacters=ye();S.dictionary=Me();S.personal=Pe();function T(e,r){var i=-1,t;if(!(this instanceof T))return new T(e,r);if(typeof e==\"string\"||Te(e)?(typeof r==\"string\"||Te(r))&&(t=[{dic:r}]):e&&(\"length\"in e?(t=e,e=e[0]&&e[0].aff):(e.dic&&(t=[e]),e=e.aff)),!e)throw new Error(\"Missing `aff` in dictionary\");if(e=br(e),this.data=Object.create(null),this.compoundRuleCodes=e.compoundRuleCodes,this.replacementTable=e.replacementTable,this.conversion=e.conversion,this.compoundRules=e.compoundRules,this.rules=e.rules,this.flags=e.flags,t)for(;++i<t.length;)t[i].dic&&this.dictionary(t[i].dic)}});var yr=g((Jr,Ke)=>{Ke.exports=We()});return yr();})();\n"
var JOTPIN_AFF = "SET UTF-8\nTRY esianrtolcdugmphbyfvkwzESIANRTOLCDUGMPHBYFVKWZ'\nICONV 1\nICONV ’ '\nNOSUGGEST !\n\n# ordinal numbers\nCOMPOUNDMIN 1\n# only in compounds: 1th, 2th, 3th\nONLYINCOMPOUND c\n# compound rules:\n# 1. [0-9]*1[0-9]th (10th, 11th, 12th, 56714th, etc.)\n# 2. [0-9]*[02-9](1st|2nd|3rd|[4-9]th) (21st, 22nd, 123rd, 1234th, etc.)\nCOMPOUNDRULE 2\nCOMPOUNDRULE n*1t\nCOMPOUNDRULE n*mp\nWORDCHARS 0123456789\n\nPFX A Y 1\nPFX A   0     re         .\n\nPFX I Y 1\nPFX I   0     in         .\n\nPFX U Y 1\nPFX U   0     un         .\n\nPFX C Y 1\nPFX C   0     de          .\n\nPFX E Y 1\nPFX E   0     dis         .\n\nPFX F Y 1\nPFX F   0     con         .\n\nPFX K Y 1\nPFX K   0     pro         .\n\nSFX V N 2\nSFX V   e     ive        e\nSFX V   0     ive        [^e]\n\nSFX N Y 3\nSFX N   e     ion        e\nSFX N   y     ication    y\nSFX N   0     en         [^ey]\n\nSFX X Y 3\nSFX X   e     ions       e\nSFX X   y     ications   y\nSFX X   0     ens        [^ey]\n\nSFX H N 2\nSFX H   y     ieth       y\nSFX H   0     th         [^y]\n\nSFX Y Y 1\nSFX Y   0     ly         .\n\nSFX G Y 2\nSFX G   e     ing        e\nSFX G   0     ing        [^e]\n\nSFX J Y 2\nSFX J   e     ings       e\nSFX J   0     ings       [^e]\n\nSFX D Y 4\nSFX D   0     d          e\nSFX D   y     ied        [^aeiou]y\nSFX D   0     ed         [^ey]\nSFX D   0     ed         [aeiou]y\n\nSFX T N 4\nSFX T   0     st         e\nSFX T   y     iest       [^aeiou]y\nSFX T   0     est        [aeiou]y\nSFX T   0     est        [^ey]\n\nSFX R Y 4\nSFX R   0     r          e\nSFX R   y     ier        [^aeiou]y\nSFX R   0     er         [aeiou]y\nSFX R   0     er         [^ey]\n\nSFX Z Y 4\nSFX Z   0     rs         e\nSFX Z   y     iers       [^aeiou]y\nSFX Z   0     ers        [aeiou]y\nSFX Z   0     ers        [^ey]\n\nSFX S Y 4\nSFX S   y     ies        [^aeiou]y\nSFX S   0     s          [aeiou]y\nSFX S   0     es         [sxzh]\nSFX S   0     s          [^sxzhy]\n\nSFX P Y 3\nSFX P   y     iness      [^aeiou]y\nSFX P   0     ness       [aeiou]y\nSFX P   0     ness       [^y]\n\nSFX M Y 1\nSFX M   0     's         .\n\nSFX B Y 3\nSFX B   0     able       [^aeiou]\nSFX B   0     able       ee\nSFX B   e     able       [^aeiou]e\n\nSFX L Y 1\nSFX L   0     ment       .\n\nREP 90\nREP a ei\nREP ei a\nREP a ey\nREP ey a\nREP ai ie\nREP ie ai\nREP alot a_lot\nREP are air\nREP are ear\nREP are eir\nREP air are\nREP air ere\nREP ere air\nREP ere ear\nREP ere eir\nREP ear are\nREP ear air\nREP ear ere\nREP eir are\nREP eir ere\nREP ch te\nREP te ch\nREP ch ti\nREP ti ch\nREP ch tu\nREP tu ch\nREP ch s\nREP s ch\nREP ch k\nREP k ch\nREP f ph\nREP ph f\nREP gh f\nREP f gh\nREP i igh\nREP igh i\nREP i uy\nREP uy i\nREP i ee\nREP ee i\nREP j di\nREP di j\nREP j gg\nREP gg j\nREP j ge\nREP ge j\nREP s ti\nREP ti s\nREP s ci\nREP ci s\nREP k cc\nREP cc k\nREP k qu\nREP qu k\nREP kw qu\nREP o eau\nREP eau o\nREP o ew\nREP ew o\nREP oo ew\nREP ew oo\nREP ew ui\nREP ui ew\nREP oo ui\nREP ui oo\nREP ew u\nREP u ew\nREP oo u\nREP u oo\nREP u oe\nREP oe u\nREP u ieu\nREP ieu u\nREP ue ew\nREP ew ue\nREP uff ough\nREP oo ieu\nREP ieu oo\nREP ier ear\nREP ear ier\nREP ear air\nREP air ear\nREP w qu\nREP qu w\nREP z ss\nREP ss z\nREP shun tion\nREP shun sion\nREP shun cion\nREP size cise\n"
var JOTPIN_DIC = dictionaryPart1 + dictionaryPart2
function jotpinExcludedMarkdownRanges(source) {
  var ranges = []
  var lineStart = 0
  var inFence = false
  var fenceMarker = ''
  var fenceLength = 0
  while (lineStart <= source.length) {
    var newline = source.indexOf('\n', lineStart)
    var lineEnd = newline < 0 ? source.length : newline
    var line = source.slice(lineStart, lineEnd).replace(/\r$/, '')
    var fence = line.match(/^\s{0,3}(`{3,}|~{3,})/)
    if (fence) {
      var marker = fence[1][0]
      if (!inFence) {
        inFence = true
        fenceMarker = marker
        fenceLength = fence[1].length
      } else if (marker === fenceMarker && fence[1].length >= fenceLength) {
        inFence = false
      }
      ranges.push({start: lineStart, end: newline < 0 ? lineEnd : newline + 1})
    } else if (inFence || /^ {4}\S/.test(line) ||
        /^\[[^\]]+\]:\s*\S+/.test(line)) {
      ranges.push({start: lineStart, end: newline < 0 ? lineEnd : newline + 1})
    } else {
      var linkPattern = /!?(?:\[[^\]]*\])\((?:\\.|[^)\n])*\)/g
      var patterns = [
        /`+[^`\n]*`+/g,
        linkPattern,
        /&(?:#(?:x[0-9A-F]+|\d+)|[A-Za-z][A-Za-z0-9]+);/g,
        /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi,
        /\b(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/|www\.)[^\s<>()]+/gi,
        /\b(?:localhost|[A-Za-z0-9](?:[A-Za-z0-9-]*\.)+[A-Za-z]{2,})(?::\d+)?(?:\/[^\s<>()]*)?/gi,
        /(?:^|[\s(])(?:~\/|\/)[^\s<>()]+/g,
        /\b[A-Za-z]:\\[^\s<>]+/g,
        /<\/?[A-Za-z][^>\n]*>/g
      ]
      for (var patternIndex = 0; patternIndex < patterns.length; patternIndex++) {
        var match
        while ((match = patterns[patternIndex].exec(line)) !== null) {
          if (patterns[patternIndex] === linkPattern) {
            var labelEnd = match[0].indexOf('](')
            if (labelEnd >= 0) {
              ranges.push({start: lineStart + match.index + labelEnd + 1,
                end: lineStart + match.index + match[0].length})
              continue
            }
          }
          ranges.push({start: lineStart + match.index,
            end: lineStart + match.index + match[0].length})
        }
      }
    }
    if (newline < 0) break
    lineStart = newline + 1
  }
  ranges.sort(function(a, b) { return a.start - b.start || a.end - b.end })
  return ranges
}

function jotpinSpellingCandidates(sourceValue) {
  var source = String(sourceValue || '')
  var exclusions = jotpinExcludedMarkdownRanges(source)
  var exclusionIndex = 0
  var candidates = []
  var pattern = /[A-Za-z](?:[A-Za-z]|['’](?=[A-Za-z]))*/g
  var technicalWords = {
    ftp: true, ftps: true, http: true, https: true, localhost: true,
    ssh: true, uri: true, url: true, urls: true, www: true
  }
  var match
  while ((match = pattern.exec(source)) !== null) {
    var start = match.index
    var end = start + match[0].length
    while (exclusionIndex < exclusions.length &&
        exclusions[exclusionIndex].end <= start) exclusionIndex++
    if (exclusionIndex < exclusions.length &&
        start >= exclusions[exclusionIndex].start &&
        start < exclusions[exclusionIndex].end) continue
    var before = start > 0 ? source[start - 1] : ''
    var after = end < source.length ? source[end] : ''
    if (/[0-9_]/.test(before) || /[0-9_]/.test(after)) continue
    var normalized = match[0].replace(/’/g, "'")
    if (technicalWords[normalized.toLowerCase()] ||
        /[a-z][A-Z]/.test(normalized)) continue
    candidates.push({word: normalized, sourceWord: match[0],
      start: start, end: end})
  }
  return candidates
}

var JotPinNSpell = null
var jotpinChecker = null
// Keep product names and common JotPin/Omarchy writing vocabulary available
// in every installation without treating them as user-added personal words.
var jotpinBundledWords = [
  'autosave', 'autosaves', 'callout', 'callouts',
  'CommonMark', 'commonmark', 'GDScript', 'gdscript',
  'GFM', 'gfm', 'GTK', 'gtk', 'Hyprland', 'hyprland',
  "Hyprland's", "hyprland's", 'IPC', 'ipc', 'JSON', 'json',
  'JotPin', 'jotpin', "JotPin's", "jotpin's", 'KDE', 'kde',
  'Lua', 'lua', 'mdast', 'micromark', 'npm', 'nspell',
  'Omarchy', 'omarchy', "Omarchy's", "omarchy's", 'PNG', 'png',
  'QML', 'qml', 'Quickshell', 'quickshell', "Quickshell's",
  "quickshell's", 'strikethrough', 'systemd', 'todo', 'todos',
  'Wayland', 'wayland', 'xdg', 'YAML', 'yaml'
]
var jotpinPersonalWords = []
var jotpinIgnoredWords = Object.create(null)
var jotpinCorrectCache = Object.create(null)
var jotpinCorrectCacheSize = 0
var jotpinCorrectCacheLimit = 4096
var jotpinCachedSource = ''
var jotpinCachedLines = []
var jotpinDocumentInitialized = false
var jotpinDictionaryRevision = 0

function jotpinNormalizedWord(value) {
  return String(value || '').replace(/’/g, "'").toLowerCase()
}

function jotpinEnsureChecker() {
  if (jotpinChecker) return jotpinChecker
  if (!JotPinNSpell)
    JotPinNSpell = Function(JOTPIN_NSPELL_BUNDLE +
      '\n; return JotPinNSpell;')()
  jotpinChecker = JotPinNSpell(JOTPIN_AFF, JOTPIN_DIC)
  for (var bundledIndex = 0;
       bundledIndex < jotpinBundledWords.length; bundledIndex++)
    jotpinChecker.add(jotpinBundledWords[bundledIndex])
  for (var index = 0; index < jotpinPersonalWords.length; index++)
    jotpinChecker.add(jotpinPersonalWords[index])
  return jotpinChecker
}

function jotpinSetPersonalWords(wordsValue) {
  var values = Array.isArray(wordsValue) ? wordsValue : []
  var unique = Object.create(null)
  jotpinPersonalWords = []
  for (var index = 0; index < values.length; index++) {
    var word = String(values[index] || '').trim()
    var normalized = jotpinNormalizedWord(word)
    if (!word || unique[normalized]) continue
    unique[normalized] = true
    jotpinPersonalWords.push(word)
  }
  jotpinChecker = null
  jotpinCorrectCache = Object.create(null)
  jotpinCorrectCacheSize = 0
  jotpinDictionaryRevision++
}

function jotpinWordMisspelled(wordValue) {
  var word = String(wordValue || '')
  var normalized = jotpinNormalizedWord(word)
  if (!word || jotpinIgnoredWords[normalized]) return false
  var correct = jotpinCorrectCache[normalized]
  if (correct === undefined) {
    correct = jotpinEnsureChecker().correct(word)
    if (jotpinCorrectCacheSize >= jotpinCorrectCacheLimit) {
      jotpinCorrectCache = Object.create(null)
      jotpinCorrectCacheSize = 0
    }
    jotpinCorrectCache[normalized] = correct
    jotpinCorrectCacheSize++
  }
  return !correct
}

function jotpinLineEnd(source, start) {
  var newline = source.indexOf('\n', start)
  return newline < 0 ? source.length : newline + 1
}

function jotpinFenceStateAfter(lineValue, beforeState) {
  var line = String(lineValue || '').replace(/\n$/, '').replace(/\r$/, '')
  var fence = line.match(/^\s{0,3}(`{3,}|~{3,})/)
  if (!fence) return String(beforeState || '')
  var marker = fence[1][0]
  var length = fence[1].length
  var current = String(beforeState || '')
  if (!current) return marker + ':' + length
  var separator = current.indexOf(':')
  var currentMarker = current.slice(0, separator)
  var currentLength = Number(current.slice(separator + 1)) || 3
  return marker === currentMarker && length >= currentLength ? '' : current
}

function jotpinBuildLineEntry(textValue, beforeState, metrics) {
  var text = String(textValue || '')
  var plainLine = text.replace(/\n$/, '').replace(/\r$/, '')
  var fence = /^\s{0,3}(`{3,}|~{3,})/.test(plainLine)
  var candidates = beforeState || fence ? [] : jotpinSpellingCandidates(text)
  var misspelled = new Array(candidates.length)
  for (var index = 0; index < candidates.length; index++) {
    misspelled[index] = jotpinWordMisspelled(candidates[index].word)
    metrics.checkedCandidateCount++
  }
  metrics.parsedLineCount++
  return {text: text, stateBefore: String(beforeState || ''),
    stateAfter: jotpinFenceStateAfter(text, beforeState),
    candidates: candidates, misspelled: misspelled,
    dictionaryRevision: jotpinDictionaryRevision, start: 0}
}

function jotpinUpdateLineStarts() {
  var start = 0
  for (var index = 0; index < jotpinCachedLines.length; index++) {
    jotpinCachedLines[index].start = start
    start += String(jotpinCachedLines[index].text || '').length
  }
}

function jotpinBuildDocument(sourceValue) {
  var source = String(sourceValue || '')
  var metrics = {fullScan: true, parsedLineCount: 0,
    reusedLineCount: 0, checkedCandidateCount: 0}
  var lines = []
  var start = 0
  var state = ''
  do {
    var end = jotpinLineEnd(source, start)
    var entry = jotpinBuildLineEntry(source.slice(start, end), state, metrics)
    entry.start = start
    lines.push(entry)
    state = entry.stateAfter
    start = end
  } while (start < source.length)
  jotpinCachedSource = source
  jotpinCachedLines = lines
  jotpinDocumentInitialized = true
  return metrics
}

function jotpinLineIndexAt(positionValue) {
  var position = Math.max(0, Math.min(jotpinCachedSource.length,
    Number(positionValue) || 0))
  var low = 0
  var high = jotpinCachedLines.length - 1
  while (low <= high) {
    var index = Math.floor((low + high) / 2)
    var line = jotpinCachedLines[index] || {}
    var start = Number(line.start) || 0
    var end = start + String(line.text || '').length
    if (position < start) high = index - 1
    else if (position >= end && index < jotpinCachedLines.length - 1)
      low = index + 1
    else return index
  }
  return Math.max(0, Math.min(jotpinCachedLines.length - 1, low))
}

function jotpinApplyPatch(patchValue, metrics) {
  var patch = patchValue || {}
  var start = Math.max(0, Math.min(jotpinCachedSource.length,
    Number(patch.start) || 0))
  var removed = String(patch.removed || '')
  var inserted = String(patch.inserted || '')
  if (jotpinCachedSource.slice(start, start + removed.length) !== removed)
    return false

  var oldLines = jotpinCachedLines
  var startLineIndex = jotpinLineIndexAt(start)
  var oldEndPosition = removed.length > 0
    ? start + removed.length - 1 : start
  var oldEndLineIndex = jotpinLineIndexAt(oldEndPosition)
  var oldResumeIndex = oldEndLineIndex + 1
  var rebuildStart = Number(oldLines[startLineIndex].start) || 0
  var nextSource = jotpinCachedSource.slice(0, start) + inserted +
    jotpinCachedSource.slice(start + removed.length)
  var newEndPosition = inserted.length > 0
    ? start + inserted.length - 1 : start
  var newResumeOffset = jotpinLineEnd(nextSource, newEndPosition)
  var nextLines = oldLines.slice(0, startLineIndex)
  var state = nextLines.length > 0
    ? String(nextLines[nextLines.length - 1].stateAfter || '') : ''
  var cursor = rebuildStart
  var oldIndex = oldResumeIndex
  var reusedSuffix = false

  do {
    var lineEnd = jotpinLineEnd(nextSource, cursor)
    var text = nextSource.slice(cursor, lineEnd)
    var aligningOldLine = cursor >= newResumeOffset
    if (aligningOldLine && oldIndex < oldLines.length) {
      var oldLine = oldLines[oldIndex] || {}
      if (String(oldLine.text || '') === text &&
          String(oldLine.stateBefore || '') === state &&
          Number(oldLine.dictionaryRevision) === jotpinDictionaryRevision) {
        for (var suffixIndex = oldIndex; suffixIndex < oldLines.length;
             suffixIndex++) nextLines.push(oldLines[suffixIndex])
        metrics.reusedLineCount += oldLines.length - oldIndex
        reusedSuffix = true
        break
      }
    }
    var entry = jotpinBuildLineEntry(text, state, metrics)
    nextLines.push(entry)
    state = entry.stateAfter
    cursor = lineEnd
    if (aligningOldLine && oldIndex < oldLines.length) oldIndex++
  } while (cursor < nextSource.length)

  if (!reusedSuffix && nextSource.length === 0 && nextLines.length === 0)
    nextLines.push(jotpinBuildLineEntry('', '', metrics))
  metrics.reusedLineCount += Math.max(0, startLineIndex)
  jotpinCachedSource = nextSource
  jotpinCachedLines = nextLines
  jotpinUpdateLineStarts()
  return true
}

function jotpinRefreshDictionaryResults(metrics) {
  for (var lineIndex = 0; lineIndex < jotpinCachedLines.length; lineIndex++) {
    var line = jotpinCachedLines[lineIndex] || {}
    if (Number(line.dictionaryRevision) === jotpinDictionaryRevision) continue
    var candidates = Array.isArray(line.candidates) ? line.candidates : []
    line.misspelled = new Array(candidates.length)
    for (var index = 0; index < candidates.length; index++) {
      line.misspelled[index] = jotpinWordMisspelled(candidates[index].word)
      metrics.checkedCandidateCount++
    }
    line.dictionaryRevision = jotpinDictionaryRevision
  }
}

function jotpinAssembleCachedResult(metrics) {
  jotpinRefreshDictionaryResults(metrics)
  var candidates = []
  var misspellings = []
  for (var lineIndex = 0; lineIndex < jotpinCachedLines.length; lineIndex++) {
    var line = jotpinCachedLines[lineIndex] || {}
    var localCandidates = Array.isArray(line.candidates) ? line.candidates : []
    var localMisspelled = Array.isArray(line.misspelled)
      ? line.misspelled : []
    for (var index = 0; index < localCandidates.length; index++) {
      var local = localCandidates[index] || {}
      var candidate = {word: String(local.word || ''),
        sourceWord: String(local.sourceWord || ''),
        start: Number(line.start) + (Number(local.start) || 0),
        end: Number(line.start) + (Number(local.end) || 0)}
      var candidateIndex = candidates.length
      candidates.push(candidate)
      if (localMisspelled[index]) misspellings.push({
        word: candidate.sourceWord,
        checkWord: candidate.word,
        start: candidate.start,
        end: candidate.end,
        candidateIndex: candidateIndex
      })
    }
  }
  metrics.totalLineCount = jotpinCachedLines.length
  metrics.totalCandidateCount = candidates.length
  return {candidates: candidates, misspellings: misspellings}
}

WorkerScript.onMessage = function(message) {
  var type = String(message.type || '')
  if (type === 'init') {
    jotpinSetPersonalWords(message.personalWords)
    jotpinEnsureChecker()
    WorkerScript.sendMessage({type: 'ready'})
    return
  }
  var checker = jotpinEnsureChecker()
  if (type === 'check') {
    var metrics = {fullScan: false, parsedLineCount: 0,
      reusedLineCount: 0, checkedCandidateCount: 0}
    if (!jotpinDocumentInitialized || message.full === true) {
      metrics = jotpinBuildDocument(message.source)
    } else {
      var edits = Array.isArray(message.edits) ? message.edits : []
      for (var editIndex = 0; editIndex < edits.length; editIndex++) {
        if (!jotpinApplyPatch(edits[editIndex], metrics)) {
          WorkerScript.sendMessage({type: 'resync',
            requestId: Number(message.requestId) || 0,
            sourceRevision: Number(message.sourceRevision) || 0})
          return
        }
      }
    }
    var result = jotpinAssembleCachedResult(metrics)
    WorkerScript.sendMessage({
      type: 'checked',
      requestId: Number(message.requestId) || 0,
      sourceRevision: Number(message.sourceRevision) || 0,
      candidates: result.candidates,
      misspellings: result.misspellings,
      metrics: metrics
    })
    return
  }
  if (type === 'suggest') {
    var suggestions = checker.suggest(String(message.word || '')).slice(0, 5)
    WorkerScript.sendMessage({
      type: 'suggestions',
      requestId: Number(message.requestId) || 0,
      suggestions: suggestions
    })
    return
  }
  if (type === 'ignore') {
    jotpinIgnoredWords[jotpinNormalizedWord(message.word)] = true
    jotpinDictionaryRevision++
    WorkerScript.sendMessage({type: 'wordChanged'})
    return
  }
  if (type === 'add') {
    var addedWord = String(message.word || '').trim()
    if (addedWord) {
      checker.add(addedWord)
      var normalizedAddedWord = jotpinNormalizedWord(addedWord)
      if (jotpinCorrectCache[normalizedAddedWord] === undefined)
        jotpinCorrectCacheSize++
      jotpinCorrectCache[normalizedAddedWord] = true
      jotpinDictionaryRevision++
    }
    WorkerScript.sendMessage({type: 'wordChanged', word: addedWord})
  }
}
