#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

echo -e "Grade for $BASE$EXT: $(cat grade)"

cleanup || true

exit 0

__TESTBENCH_MARKER__
� `�[ �=�V�H������X���cfp�0���{CVGHmЍ-y$�dy�=�׽��}��ح��[jن��:g����������ZIh�����X~�՞</���o��ZK�+�'�����[��ʋ'��������Hʞq�8!O����r�i��'I�?	�A�U���󿺶�8�����<r<ڼr�����6�/^��m�������O>�sO���`�̉/*��;��ve��w�՝_�l��?�ί�����������^o�ǭퟺ�k�Hu^�V���NR�e�^.����#�? ��J�N�C��BH<�tD�Y��:�I^���b@�gu>T�0��Oj%��5�� ��EH��a��%���p�4�G4r/$CǏ�xHF��������H+�$�@�T�	ad2��N�S�*I(%MGe5��C��_8��M��������1���OH��*r����litN����)�{}����<��y��_yu��ӳޜ��R��W*��ޑ�o �)\��ϭ���8��s�䈀��	�ހV; 
}9�>�ޙ�~��I��΂�M��2��T�!"�����Abcgd��0J�0��ޙkރ� �q9���U���e��i�t� �ABj�`?�^���{���yZ�ٻ eS�������U�
.y�i�I�4�x����ڶm�L�
lL�F4G[���E��\���$�b۲d'E��m�}}c|� ֓�g�nJ�V��M	e!n:��t<���rwS�DC�8'�_^o�tە��ãn+3F���B����#�����+�,j�����j�0=H
���E��*&|�T���U�ju�*�����pc$z_u�X9���)�ra���9�S:&�e����*�
�gB>�"?H���li�Zm��M�⫴:�=,̀�Va)"�>L1�H7�"���!8��R�|�k+�c���� E+d��&^>]j���Ͽ��dSS��t���x2��|�I¨��-]�Kh�ן?/����������h�����G�Ķ������urpd��O~��o��_�ve�}X���9?pc�X�ŉ�D�K�J:�X�T�����?��V�^8Q���gu*������F�ǚ�R*E_�>Xgc�ek^8>k�^ �]�݄m`���M�$]9�{a��$H�8��� t� �����I8���Ðc�2G��r����寠�&��^�����[����o���C<���C}�:qL�D/��<_���B��w�bE��K�hx�F�x��������㈢�+�sf4erf����*816� ��W�����3�]�N�F_�	��]���ˑ��(�@WF�:p���Q9A�p���8b�3 k�/�UME�$f��؆��Dϊ������c�6�K
�$��\-��Y�F����qS�%|ܬ�@��ϖ��_^�'���T���R�:�j�wF��Qd�{A0�j�7
�� �fv,Dzۅ�*��'7FW�#-���x+�c���"�n���R������Tl������
����~R�NJ[0 k����~T9Eb!�1�hmA�)f���ۄ���]ņ�'��A��pw� vJ[��QB�����{�f`����������qy��1Lvn�Y�>ԂK��El (N�h��o��� �P%UK��+�� ��{�K�9�Q֯���ެ!Wh��b{���Y����J&�(��������m^���Q+/��N
p�D@��<��yO�D. �8�u���8�@����_J}VNB��ްͿB�핢��}�N�E=���}$l�xOO��qD�eJ<�X�̭XjT��(�sp�k��dp�4�eRcu�UU]�ɗ,�3���s�G#�X�p\�(��)�ݶC��o��0�O���Ji��ajی�?����n7��>2�J�;���6�nTu%�Č���*]^	�5eP (��`kP��\�1 ��77���2�|�0v�%��z�6n} �m�jo�bg������t:�A���b���M�D��-���Y��F�\l̦��ް<>������.�~����_i�����������KMsY�O�����`�,ŀ?�ɷ�����x��g�\z���9U�xd�DԦ��e�Ծ��x|v=jK�\�a}��<�q�͕Ft�\S�2���ƀ^)���R������lkL����@�]��T=37�7��3�"���G����1�]�k�^w�M����k:`�'4tN�7�rJs���e�]#�6��6���]bn:[�)�NLy��v'%�#6��1By���r���ޢq�;�A�)zG����.y�/'�&�i"闓���̔F�Uu�U�ԏ�W{L��\�ni��~��z����`�W���V������aW̾='��0vH�"O˕�Ø+�Bܲy���V����u��Nw�Ɩ:�����h6�"gԝ�-�W��3`�e�b����^wm��q�~{p��_��[bﾵ���7G۽�J��m�/{ņ��G��}��������������뿽�x�� ���?<y}���)u��zt���)��j�u`aQ��|G����4g��0����ѫ���JIq�W�$'4Θ�.n�^�xCj9`Rv?�j�̎,Yx�V��b��vTy�{f'V�؉���"_��:�/�'F��#z�а��(�����&��{��)�'^xL�N��H�I�x���c}G�U���M �:�iQAD6P�!� qB���G���=��2��T��#1ٖa�ok�pVpJ?�F��O��9D��TKB���"4c�X����Y�
À��9¦���WT����G|&������f�WV�[���6T?��xLY6�Ū�-(�F$ �,9h4p��:��� -{Ȝ�:�+��-�b��g��j!:i��u�Q�_Ҭ�Ud��8Hx�������LX�$.=�Bܪ�ֳ�@����1�Iɉ�L �3L�f�=fNNpđl�B��g��
9�����B�����n~��o4�i�~~s�{k�����d�W﨣[L�|�⮷��N �L���$���ƙ�-G�]c�4[廷�[��C4'�NE�E�Igqr{�d��s����;��(�4,�
h�-��yPc�3Ij5Ӻ�[�s���m�(�2w��v�c'���;������6�&V� \�}Z\����yDyO��M�b�uo�'{�w|rt����=��nx�`s4�3�)�~���'4��t@C�g1	B¦�<f���p�9��O/ļ	c4]y�"������u6��
眅,}��c��������֏{���x�`ҕ��H�J��<m��M�H��0X,!/Aud��eҀi�`�U��Bl�b���L�V�=�K!�S�R=J��v���a��� va�=h�V�n0!p*��%J��c?��|��~st��מ�I�LTޔ<-j12�a�`|m�)K���р�q��㓭=�I3W&3�c�ْ�d��Z���䫍���'C��V-/�䊒��]2h�\P��ϒa`��WrEc�`i�a?/ۖ�|�9�փ����+��0�} ���R��I/'N�"�dw��D#r��pLj_�m�hj#g d��v/h������b8��`g�L]'���U]���Q��4�0��f!{B��ǠD�8�
�	f�<��?U�qX��h]§�<�|��B�\I�ֽ_����<p��ۊ���-��.� ��#��.��=��bi��c�V0�a��Xܽ��c�`� ��� ��8;�Q�.�Uz��^�d,�Δi���4�����mVt�l� KSF���q�d��0+��@�.Aɘ�na�,����ͥN�r���S}CB s;J�w��^NyK[����\���s9ӊ�_,d�Fu���.�[��/���g�j1�[qڐt"8]�(q�g�I�\�"�!�(NEd��B0��ƒ'�Rw19)s��5Ld�[P��-�Y�6B[��Y��=<��49`^�b�G$�1.�D��Q���3?��Y�<��ָ!Vw6�ŸҭG��f;{(��8#��8)rI�J�X�2��C��e~�E[>GƜM�n�X�o�������x8��-8X	��P-b����;	2-a_�����}� հN+��o���:s[tI<:�	-�UVzU϶1�����3,ɀ){u�r���z�BK�l��^k+����r'���/���^n��;�<��P@Y�9jXo;��J������u�-�Y�˘�kT�]U�˜_�f��L��E��f=h����U�F�1u��~�?�G��ld:����é{���Q�}�LfK�
-(���:��K���EE��(-R��JLy��.�°q��.,�D������@
�+�՛m���JX����Z���e�Y<:	�1������)�	Y�c�9�p`���	���%xfAΙQ�$�s�D@%�� V����Q*B�9%�]&5
�S��EKM�"k����F��L����9J3(y�P8ɼ�Q�ټk"̯�N߻�^�E����$���"Ke}��u����l��	���&y�i^�/�rͬ�Y��9�b�w��I'�w�F��g�cQ'1�����+���|�|F��^���a�!�.��4�:2z= 3�X!�E��X~q8��Y�m�G��[>ذq�^8��N����e'ӣ�~�|?	�2�S�V�_��Oq3>�R�BN&6�%+w��)���H���ߘ���*1�k���-�\NF��6fr�&4��(Q5���`E���l&?�4�=!�]� ]^�g5v�4bk�\�o~�Yc�g�iw/}L���j�=_��ۃ<��{[����[��7@4��|	�,���5�GuѳS�\����p�I�����:;�,5f�%�(��x��7/r �q]����S?�c�����^�^�ȩ$>�:�/9�P�Q��7@��jX�dnFWv̾f�lS�Y*���N�Ы��&ɞb7�l����I �����V*x���%�꘰�HL� �����g�!f}΅Y0t+�&\��bG��8�uYvyC]ŏ�7���d�� �}��^�������<�3���kη���~���ܧ)A��/��Z�=�Ot����F[�]
㽬Θ�Qn$1%�sf�lg�Jp"~�R��q����rh`��|n��2�;�겾ů��}2��y;�YqF�~�Ѿ�	�ҹ�_�42��f濷ɿI����ٔ��y:�O��$��u-6���g��Y�}�_��\�o��V��j{V���؇�5���o��-X�������q�)g��N�N�8�OHMv�	anH�e�Ւ�<�U~羕c 5[������:Qɝ.��,�ʡ��u�qb&4"W������\8��p��h�A}$��9fg�2q:#3f�2�eyS
sD�;s��{�B6H{�cj �A0MP��� �ݏU���n*��͌AP����%p
�T!��ՕEnʘ���!��>Yp�\�}lN�����6�QC���Y��ݳ� �%U���5��G������A����� >-�������>��_�1~��˯_O�V������@g��3gБ��,d�.��;�C���QǗK��3N 4|���)���oy�:QLٷ�S�Q�GkfH&9����:����>�|���2�7��g�J����E�|:H`s�0t�#i��������u�}�B׳_�9㎼�E��A>��}AFb�2��9��,ګ���,��$2�y��@�w��y�yH�y���tH�*3���V�9���_�f���ٷ�3�rb�Ǜ�u3�s�5L#~!�F�ۃ珜T�Q{�Y�s�)�L�A4�dU��~�JK~�a$��18�؀]��xW���Ҹ:�+��z���r~��	ƣ��(�*���eiw����[y�<�����@���������"����յG����˽�W�]i�I�4Zd�ُ���wϋhW�t������7'�7y����r0$�������q�R�#�8ƴ�1��}����(r`/=���_��o0;ѯc��ВhD�@� �<��٣�3ܣS�����Pj�s$	A��a~��H(�'[�D �����Ӕ�%$��X	�҇��Ə( ���6#q����F�ϋ���z�`@4t>�{W���E�3�b S�4�NQ%�)���T�	��j�;q6x=�~�?&O�H}���W���sg?�$�x��T�B�;��9��;�z�=_�c�D�±�{����[d��'�7P�\�� uϊb>)O�l"ȣb��pf���0I����"�,\PYn�L�1���bJ��;x�{�tpp�?��}R&�xػ����Eff!3�k�:53�3���-0�����w���EG��b}/��@{!�����u����T�Eff�!]�F4��R�7�q|��+�~�z��O�;I'��ɬ�|=s��s�x+���>�"��~�lp������GPdn��<�}R�1��W�BtU��S�������~roPn<��) �Iy
��A�����@��\lR�љ�ш��.��~b��5���s>�*E��
�?�q�a�G�18�;7�+V&�&_����%�+"Ӂ��.U���Y����U�d�>�d�h��a��A�
��fCIj��A��./�&f�#���Ki�R{Uߩ���y�?B�ݹ�Ň���H2��q*�7�F"b���)q�eӆ��R�",�9G�����0��9&��y����5`�n�/WjuEʑ���bV��܍��P=�������<p��0�~jk�4��ⷔU§.o�B�`\��t}��^x��+�E�JrN�E�mn������	�DPT��<�y�}���9n����1���49i����_�-��Av���н�J� �m�6�����-��v�E0�-��lE��k~������*,)�Oq����BJ�	'�$�TJ��O�s���>� ���Yc� ����W��l@����$#������4��q�_��p��~��,� lqd2h �6��G	��<n���mx�����C,�bͣʀ�d��/��tq�v���VC�gI:7�$�	��JT�59�;�xeŐǋ?@�S`�0)g��EV�\��t�#�-��e�D���LpՕ`��i`�|bhg/�!ְ�H9h�(�mθ��[l �W R��SM=�poj�D, �>�zo���uB�>*R
��x/^���>[Y�|�R���*u�!�b��v/~.9۩�� N���r^�ȥ��Y��#���\�F�K!�A�S'���r����k��p�����?��6����`k�[��'�έ!(v/;S��-��ԏ��l� t����"�Ӟ:�+n�_�.b�Ic�mu�Ⱦ��MVȶ�<]j�n��d������2��T͹��K}��F!��K),)�!���K�h��`�S��$,Uc3�y������
��{�Vh�����S�U#�O~��}����F�G���L:��N��}��Z�?^�ӴbG���:<?=�=�����Nۤ2e8u6�Ń��:��ӻU���5��;z#���6���,�%y!K�X�oF�<��-�Y���FI�Ԑ�JW�ҕ�t�+]�JW�ҕ�t�+W���Kl �  