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
� �Ļ[ �<�r�F�y~E����]�eK�Y�mdR#�I�l
�"b܂�dˣ�����L�>lM��~l��� AJN���([ �O�>�>}dL���z����v���������ջ���ll�nmv7�����lo|Ez�IٕD����wv�����W��?�}'�]�����������r���"4,ڸ2����q����f���u;_���#a��o����s�k�Ѵt|xЯtJ���^��-�^�������/�����������w�J���C)Wdk����$iY���%�S��!��푊џI����/9���f�� "xz�n���x[�|���	� �xJ=@DͩO��~���%uHl��O�:�Q@Có|�vD�~b��f��
ie�K��H��hBل܋pI��� �JbJI�PE� ��0��#[�%���wvL:ȓ]�؄�XC�$�_��0eå�?���������������,����'{}�j�a@Z���^��5`
W&g3��Ҏ"ۻ ̎�Q��`{-��)8T��L(����2L
5�>�_E��&�6�R����=�4J�X��H��ƶ��|��{� n�3tG�n@_i�x&vA��{1�b�U� {6xq8ԏ��"�(�L!ؔ��曕��Jg�,t��M �1!Ұ��qJ�m�
8��+����8	=����"6l�+�&a�;ժ�d����>�m�E � �fR���1�Ą�lxCBU7u"z7%P�y��)�B)������������~;[�ʕo�"�3v*G�����ed堺�P*�9��0�I�����T3��S���jY��ݩW !��s�2�H2�s�b� /&b4��ʵ5��&�S�������*�
�g
!����	yS^mv'o�u�f�)W���+O�5=J�s��X&�bj��'�S@��)��H��9�*��3 4��5�����n�Z_W�d7(J��#�Ǖ����c[F쇍��9�$s�"�pss����|8�����/���V�g�	������ƣ}<8?��տ���
t�་!J+�g:	D�'Ql�Es���aҍ-�A@�J�L��u۳c� sj�5��^u�t��V܂���vʠ��7q!هչp����'簚� +�sY��9>$$�Q3*D�͂zO̘m@`�a�GE�\�9��c�/�"�H��Z8��� �hɒ�����A����>��	ۇ�����c�3���/��[�v,/��a��?���#�6){�X�p5�" u���Ձ�:Q��3\�\��5���U�������t1g��z�8����>L<ݜ��_���U���ѠV'hS��2��0.0�5P	�VG���+�6�*Og�Y>�G�b��bA!�d�&f_Գ Kh�ƗZ��j��]���̱|����6����n����9���m���ۈ�S�|,�1�m��<�F�ЛA�1�p�m�g��|�k�ә��Ɲ\k�0c-c:�s�,�Gp{y��V>]�}�6q�KA����[č0P,u���`�5&��!��px8��� �U7�ښ�04�DuҮ��ѧǇC�mo��F�}5���'G�G�ྑ�*��!�إ��@@�.l����21�AY�H�WGG��G�����Y(�<��[�%[�
��R�>�h{"��P�]v!��99�����-�YM
�M;��|C��{�u��ʑ�sd?�^>A�,����s��n@��4�Q�TFi9	��d�t� ��Y3$'��5��`��B,)�s�r�<ߘbg=,� �m�$D���>�|�1�5���Cr"Ǳ;��2�+�n?�ʯ���y1�	���
	�4����l��,�,��S^���"�6 �⡼8[+�@]��Ld7�gR���K=�$keHa���2/�
�I�v�r��_�0 ��!U�N�M��d���M��������)\|�����OQ��S.dP[@��=r*x݁E��F>��)6�q@JX�M�L|�5�Y� Ng����/h���K��ttGxz-@�3�O�~�}���D��i�.Ub�zg��y�?8B�Fb�rF�<�������c�(�j(P<r�D�
W"p(�(��\
 �DE،���DS:�yS��p���:Iv��VPV��AMNq�8��S:��'�7�o�r!K0eJI�T��V3�XSj���kBt�^SP'b�-2EцAc��*��<�d)I.y��_ ���&���x�D��b�T�Ĕ���8�?0�Vvd�L�YMc���X��3z��s�kq$��r[P[J��R��:����E��Uږ#�B�����4Fm�-/G��x4<ܯ ���L�����$�����G��OP\���_��|S (H�[A��*!��G�]�$�
H>�<�L�G�!�� (SSgk�OƲ4��R�N/O��ƋͶ�'*pC�]��ƭ�Sݘ��FU..P�(�
�
�Y� `�R���T�]`���l4-(�3E�DQ�1�ԋ�!cL�!M?G��_TU���?>�J�� �= �wUR���p��xo����D���j�h����sۙ�d5br�=?�SS�ۈ���ZK�������͓3�"�N���G	�Rœ����r�v��Q����K�\��V���>	��P�p~����P83�+�*ZߥG����S�`�]U�ſ��:+��)�ѡ'R�Fp�/�F�;�(�5x�Z�v�^�w�l����ۜ�c����vQ�U�X ,>���gl��ot57��mnl`n��v�d��ق�^��cv���fs�Qo�vo��[x�ln
T��v 6��7�x{���m���!����G�m��:�����zݛ�3%$Z��q��)?�ڳ�jK�p����0aWb���s����RQ��I!��j��1./�"{���j6k����Y_z�����zZ\�9�uo� 
��J����9	���gd�j16Fԙ!��]��∳��8�Iqg�����a� � �bj���S �5�V�6�����p���N3�y��N4���D*x�=�$�Ղ�z��:��1|b��A)$J|c�jN�Z#_�Sc^���h�,�>V&ߪ%
hU��O`�s�L=[��s�8�*�6������%������/��ƒ��bm �}[�P- c�k���IP�9~V�@���R`B��`Q%$L[L!��3� ��Y���\	��l�`�(m��j0�h�c��]�E�W���}��߻�۽�����������r�-=���1�|�k�Io�a�c�v�y������O��{o�p��1B�=��.3#0�2BK��m��ܚLh ���C�5]	:�k�[��¬������K��E�Dp)JiV�иp�`f8uX*R+ao�k��0�z�%���Lɀ���E�ϽH���� K�Y�DZD&F�9�,���Y,W)<�e��!郧s����0A{ⰕiR��0������WFw�0(��J�{�pb����D[�)e�c��X�W�@*
�&s��]��� 9(�^E��6,	���R�O�0��о4b�[�L�9���%-�>�a��*Q�3�/�oqF�k��'-EVknF�����<����{?���e��U�2���0�!OS�f�,�'4��va��#(*��K�{�8�T�(���
�B��
��x��(�ig��A*�Ϯx�.i7٢_��(i]Z1�OHc��Op�(��ɭ<F��V-��$��IZXPӣ�q��iI��sс#����&�q���j��hĊv�E�Sg�E)Y��';~�LÛhA&��Zj�`g�!�Z��vW���^O+�
3é磩XȮg6T��)��1,��2p~@d
~6�����2���z��U���(W��x�_U���5~J��u5~NQv�5?��(��g�r��b��jB�19_�a�=�_�(�)PY��h��-Od��ۖ�}{쉦���������ttr���GC�CP�Cj{����y7�'� ���p�q�N:�����8�@$�l�o&f+�f�5�N�lq�ӛ[����}ss��N�N�or|eG�"�:~�L�*�l�n� ������-�:>i@���Ss.�8o4Y9�{����*#�����@%�Q���g��^���^,/�r�,�	�L�gmj7����I�R��"9�-f[����P�`��D` ��F�f�E~��Ņ!F���ge�wˋ{����5u���B��aq��w�(ڙq��p����R~;o��S��8�՚@��K65��o�(�yA���i�����F�6*�
Q�0��ԋ)��S�/�LR���2��A*�|);V��.?�����D�c��9���F�`'mk�km�0�����O��_`S�.�<��. ~��X���>�)e:��	��j
���լ2pQ�<��]@�i � ,9J&�i�����Btq��G�C5C/Ċ�g�9���:0�^*|����s1t���7�i0�Є�����y˦����y����tm�>�\��6�O�����_6f���������R�!���Fu#��9�$%���M�3$��H�p���7\�-�٧ѫ��q��(q)�U�cK+d�w��?��~MC�ǻ���cÃg9)�8Ď0 ���v��@@zKٻy�f�4� ��a�ԁ@|���飒ia�;��)~g�,n�ӡ�Gv$C�ߖɄT>�|<����	���;D����z�Ȥȣ�J:I��OK͖6��<���o�t�!��I�� �x~l��u��3��>������^��1���ޗ��g�����8�7D��4t���@�qt<v�{�ǣ���}�t��dЇ4�Q���|�4؛�n@�1j���$2`�i_ӾaY�G�JG�IK��P::|������pp�G�D��V��CqI]��Ps�5'#�9�/�ś&�(Pc8 ��6�u�Cڀ�3���L��2�$�!;,��lDBُ�P�@��B�
�wi�<r)|,% :�$4B �b����!/o���l�����,�q��)|�����G��=�L�\B��� z�J��W�iۭ��t���	4=���Z�uix&�F�!9�|߸����[��c���c⍗/��1�N�۱Z�Zslq���G�f�c�AWU�gخ^�,@�?��/q;�W�+@d�����(�!�BU��)'������84��	P&5��)�[�[W0xFd�O&�5[��ژ�-;�v�9�O���T�^�N���Qw�W�@[�������60q��G1��:�c����W �4��ɹ�?��K�X�"�8����/v�2\�
\�G�#��l�Y�y�w'?�3�HHV��<�v4��m�F����E��� �D�o��gDu�;��ۿ���`�
���M)`s߂X؏�i`2�'U.H��Ϊ­)���� ,w6���\�\l�*��&O!�}~Gj���I��m�Bq�	�ƅ�=+��XGiaX�����F]����+@#�A������U�6ɟ�n&x�`Cd| l"�I�&z�F�:Qjm�[�I
mA"!D��G2b�l3���E�ƣ�3����H0>�o/��p�!8�Xg�緿�8� �����YJ��0A�l��T�������g��u�+���%p`���@T�N��\�$F��+�7����m��of�y�Z̫�%�ݝ�yo&쭧�5����M*ʯ�>�x�U��B{�s>�ǘ��;:�iDõ�=���Əx�ho����A��Xw���j���P�{םx���I������|�3՜��W�9�LevO?A��Bd����+9���*�,4 #�+�@;V�zpwQ�:�u�(����U����+��m>���0�Im�3���#��Q^`��J�f���2����j����3jv�|L=���}d����3�65�����䎒R�J�9����:K3�F�e���m":�
s=ϊ�H�ajAjNS	]�O��Z����!�p]�@�}��2�沅���=P��y3Y��؅�����v����ib0�d�A.�[h�z��Qz}��Pӊ'm���5�,�t]3����`������&b�+�����{z�i+�Հ�z��!98ּ{�l���ל[mʚt�I_��q��v;2F�<V�^�4��(��T�����Se�@ �@ �@ �@ ����V)� x  