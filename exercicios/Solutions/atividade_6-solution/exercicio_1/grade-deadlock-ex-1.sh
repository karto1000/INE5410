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
� ኞ[ �=kW�Ȓ��_�8���lɽx�������$�#�6hcK��L^Ï�g?��+�Ƕ�R��z{�:'�VWWWWUWUW�䈆�9���k���Ձ�����>��������	��66��:�������oGRr���	y�L�G7̇+k�zE��#ߟ��D����ƃ���J��"pF���q���L�ϟ�念��|D:wGB��'��㥵s�[;w���˃��r��?8<��/����_���7�������f���`��ݽ���[5T��H}Yޭ�?� 1�ڈ^�y�ɤ6���#ˍ���,3�V���!��Yf#��YH���!;1�{P�}m�{��I#�F��Dtx��K?���NH�N�?�Z��38��'S��|Jf�|�?}��݌���K�3$�M#��J�K��8�K�UQJڎ�j�ޅ���rd+;$a9C�эH����.!5v�S��7��=���B�J�?8����l�a��˥���/'�������e��zW���
��ɻ�Z{ᆡ�]�G�h6�@�&���Sp���ь)�;��E�j�~�B�n�������}	h8�D6Ff�?���=�����Xn@_m<������Cߋ���E� �O�_����r�" +�\�����㏏?^�n�a
��@L{L��=چ������Z�#1������V��h�9�W�	�ڵ,9H��7�����]F � �FR�ԕ*1a3�ޖP⦓���Qe����Z-�"�)�����Y�[�~y��$Ψ��c]�t6�e�#}��:�y���A�g�6T�5�ă� ��Y>�j�WO}٭[u�6ǫ!���L�1F����$Љ�~1�"%T���l�:�sX濸� �r>��L ��,p�hL�֟<]����n�UZ_���GI'��DLG$��П�"���!x[��. �*�Vǰ� �V���]���i���v�U';�����-��J���3qGN������;�����<���t6��������z쎽����������}68=�ip�����m�C��7������9X���h�O/w�{t�� �v�jfG��Q���4I�zV�v�#|����al�FQ�7�B���؃Y��ȟ��7g_ � 7e�~c�C@����tQziPO���a�6 ����ȟ}p�᥍����^�^x`�T�]�Y#����d�7��̕^s�����b�?��1J�����݌����ϥ�n��-��4��{`i`c��7���{�LSw�ߦA��ԍ�G��\o��c{-�4�躄��Y͙��3'��N��.Hb�?����v�ڵnm#���w�-G��#F=�jϙҖF���édOg��	��@��*�bb���O�H��Ղl��:�}j �1b����C���ٛ1v���Tv�7�B��	�7�æ� ���dd�~�/o��v<`�4h��F���&mg��N�v5|7��Mu,�D�2W]p����8��������$�R4#a�5�7(E^�\�9��-�P�Ţ,�sU0N��Bi`�_�0���#E$"�-m�h8��l�� s+��UnK}�6�oq�(&{�����vʻ{��C�}<��!m�nU`�ѫ�Þ>���i���9�������0Q�v��5
C�3��mPHh��%���� ��;��'߽��S֯D�`�XSn�D���j7Y��<a�@�ED�;��1��vy{GoG{P�pv1��d��LX��ּ#�M"W����Ns<���h���:�+i��Ih�4�k��QE��9�#�˷���'uF�[!���^�8#2&����m�V�"�k8lq�Ƶc��	�h~�d�4Z�uU�S,��$��o)c8nN�qm�8g�)�Lo%����@ֺO���u��n>���5�s<�c_��"����[�^��
/��_-��Ir����6ʅ�ȱPfCT+��F��c���������`�E�+Q2v�X�r����M�v�9����L
 ��e�|n<��l	���w�7e �ܝ�F�$<���1��>Mu�vv0�au)�tz:�^�/6�j���m6�"��������Z.vf���޸��e��'����d�����Fz����a�/�)�;���P����t�2�1�~8%[�uS���!�f.�#ۿZ䭺��##'�6���wA��y�fw��'l���>�~ q���>w��Љ�,9@��`��FN���ģ�ے�۵q��btQ)>�H�GVW9$�E�BZK�a'�!K����ɥ�Q����*B�h_����3(V��u�Ny(�@�G$�~�L�.�U]�c%�xPOAq]KTLۑ ˨t�Y�>E�>ں`���:�du�:!���11�N�Y�B�5q�E旮�7B��К��RJc���
)T��{ұ0��ޜ��e��$>�����dPa��S���Qz��n������l��M��������=�S��]י�Yt������w3FI��y�����6�=��q%Z�����d�e_Hߞ�#Xj�;&�-�OM��C���3�ĭ��t?���eu>!�r
�����Ng�O������������r|u���m-72 V���8���k���W����f��i߶_����/G����/�O^�{��񫓽A���K篇َe�#����V������_��_�X_O��������˴�{y���`w?w�����oL�8Ԩ�Rck�7!Bڍ7����a��~<��M��ԛ�9B��85�\Q�f�kSũ7(�Z����o���-1�:�KX�l[,O�Y��L҄��v"����܎�4a<'�h����:�>F�5 �ǈ�y���4� r�8�����\���a
/�������r�:�ٱ��ɩ%&ͯ�* M�*��J8d$��3n�2c፰ՐP�����$t�2L�u���N釷��i�1��^��cD�e�T+E��"4c�PQa���b>>l��v�@�BxB�]m�ن�����:Qi5�Ǌ=z�f[�*��wS�U��7;�Ϟg��փ����Te{��j��^��2Y|�z���q=<i^��VPf.C��L��:�PX�6X⏽C/��v@�� t�hr}U`����֊���<Px�(�=�Cܪ�-dV^/�C��zc�\T��pF�P�*�.����_���"u`��הA4'A=�� a�h9b.�kD!A��$��)�����B"%`Z"w������X�%�؋Wg�������h�Nt�!h�AKv�n�˲�Pks�(�v�&�;=�}J~w���y�2(������(�QlN��h��E�-0/���Zɲ�>�fRdND�����`�G�\��Jr�Ҡ����yH���Uؒ��^�֔�8�,5��R@�������냣��L���!���:6-���'AB�(�������3i�$��xA~�$x�1�?ۦ��B�/X&C��,�@%=���0�B����aB�0eM-��U���N�(�c�}���u����?8=;9����@�f7�XU�6�O�h��ݗ���\�Y?�*ؕ.�<	��f���}��t���X$��d/����=QNK���w�*�s�g��������O���	�s��J����x���z�Ÿ�lp�@8rH=��|ս���cH2d�:\
l�-nwD��k�� �^o�Z�[^EJ~Lx�tIԳ��W]_<ru�rK��#�������?`f�,NWL�in��tHқ�9�!�����o���K�wp���4۲���`Iv����z�.<H��>�Y9�\�X
qy�X@�"�Q���Ld���Y����r�&;3VJN+?�RU����K�O{�NN�6�4-�D�u��CAъ�F#������m;fI����ȣa���l�T�̕b�p�:[���<��qOI��	���:1L�c��ھO>P�Q��<U�.)�?$��p:��Jv��b�-��n[�2�����뜬<o���a��@����r�0��ĩ*�e�NS�K�C_b:��L<�u]���d�=DfW+7"lk�o��`��n�0t��">1�n,7��U�-��Jhjy�`/i��'��<����0�К�+5�Y��8�9�)�2���?'S'L���}��~)N\�|��:V���ə�'Y@� ��p�j���'` �R
���\̝`�o�¹��d��-�*�K�TȰ��)��٥$�TnfC}q��(c[��2�"�$z�1��G,���d/A�L�3?��
�
���dh���LG�M�/�e]��� -�^&���B��f6�C�R>��B��{	���mJ��<�Q2�nI��e"6�-���0C�3�`z�'>&N����.@�l�t'�>|4K>��e(xtgȃ��~��Ô>�Zb\XE+9�qqwU�9yU��(F�Dk1u��,�n��\����0�,
m���󔑛�D.�Vߣ��c8p�݂q�&KīZ�&&!"����(o�Ia�~jQ�ӆ�i�j*%���:_�q��!�JXc]-
�4�צry��V/��G��b���L���|�Ҝ+i�,D������m��������4�aT�<��r3�.XM��TYK1��b� G�C���)�<x�����L�җ\r���$��fb!�c�u���Fٮ%B_̐�Ki�`Ήx􈀝8�Ǭ�nY���JX�Uݜu���ĺ̜�XW�v��ΧS,���A}e��y��,A��'��ꭁi ��K nľ�Ulb��c2%T��Y*a�6ү�g�22�h�˩TF�#:�����1����wXI�쮔�%YV�;Ssb�G�pN;5�;�A�(�s�8��d J#�;�M?�j�:<K���Y�3?*S��M;l�܌s:�Ň�34���N����b#��}J�����&ڐ��-ł�ܺ����c�,�^?\9	 ��df:y ����$@*Ţ�Cϰ(2��ʡ�"��*Z�e|��Hg�FZ�\��/����0l���_��Ħ�͒a�����6�n�jN���q�R�-G��a��~ۊ�RL��SS�nKb|v���=|5�?0g�O����+�Ƚ�r7�.���	�J�X�R���T����=O}	$l�W�hU:LV��~���zO���	�L:gJ(�Fᯓy�k9SM��;�����k7Q�d4�<
oi:c|�*(~���JZ��$�
�֮���Fo�&���Ό�/%c��H��@�&�n/_�Ho�ޝ�y+�A��*�G��*Hbn�L1*�!O�4F�O�<p���_C��a�?㯃J�X�ﭳ�מ�����G��QRAE��;�+?-2�$ZJH�Q_����Nu��ɉ�e���)sl%�휵]b�2F��`���,�X-foo<�d'=9���r�"ju��x~=B�����q~f?����-c����R��3#|�Z�j�XE�J��r|��Z5+���ꝮC�U<�(/�L��^I[E��X�
<���ڿ�c�>��,�Z[r2r�z�%�����'��q��u(�B#2�U���PTW��ʑm�I�k�눧^ĩ�@��g�M?��F��˞��>�I�����t]R��w.SW��f e�ry�)V�Ǣ�T���9�Q���b��"�<��L��Bb�fs����dpv�b���,�*�鑵5�s��+jB³��}�j�'�o-k��~$�!��e�R��e���.D*XSM��gݪT�|[��3��QZ��jϐ�O�&����p�&����	�l�ɦ�@s5/��܌z�^$	�^`���0�QH=ژ��"٣��Ѭ�,R�(
��ԙD�[VP�մ ]:�3<�r*^+�(��/��������
w2F���:����6��q?���_����/�� �A,�KPy�g�U0��j�LϭL��W쉕��_MV�<�Yj�����b$���Z�b+�U�fA�1/��&k��֥ߌ�ٕ2�|�M����ŏ���>���Ċ}�C�kV�RR�����-����sɄ ��RV�%�3vܢ?��4�N�P��O�ID���	�t�������bU�%.ܛaXY,e�e�+�.�6d�[��5��ެ?�U�����7�����|������*|K���|y���k�h�R�L&6h�5�3��H7��{q�F�mB�&��+0��%�rV� ʾlI��!�@P<OQ���Q"��נ)�d��1~�HkK�����p)��3>��.g��9�O�A��-�����4�?�� �O��.��%�s�{\����<+�̆����S��z�?�]+�o������������g:#koa(��؟{#�@;��cro$�%���
E��p��L	����,��
�Ĵ,���\���C%-��a�ʎ���,d�e%>� >4�����wt�m����W0�S�i$���p��vӴ�E�䚴�a�h�N�J�*J�np�c�����ؗ{����(Q���z-nam,���̐CgX�O������^{��4\h��󝭼ݲ���Z}���x9,���<��^�Q�;)M�4�0g�H�~�ֶ��������<�/E���,d������ɰ���y�KO�K�r������ӷ�`���3�{���Z�}�t���ᓳ�����ؗ�>�1{,9��_�!��DHiW�Z'/�O_��$�Lxh}��Y�=;<����D���s#_�k�d*B'���Q ��eܗ�'�2I��1����PI=ÕÎE8J�-|P'��53�o�4�"��в��JD �Q�-�~������
 Kq� ��j��* �����8��ko���8�g'!�����mh��h��FX�� ��	d����9�ٰy��4t��rϖ�`B�D�����.��|�
��Y�9�&�O�������.�i>zO�Y���>}��¿�l����mm9�2�O��x�,�̈́���׈�7"�,�?�l�j��<�ؖ�B�УT$v�
 ���.8�v�(v�<�I�d\a��J6~!��)���l̯�,I���&�)��{Ùxө��''�n3���C$;-OX'�|w6���<��&�M�Z���D �W �Ҫ��*u,�p��a;0��c����D6
})1��`n 8h�$�x��2<oj���b����}|@?d����zձ��oO��m�͘�P��l���"�p�h�d6���XL�.��j�啀�·�UfǬ��{t���Ɓ��zbڝdA�ɥ�@�E�!?~0�Ha�L|8Ĉ���_��T>�/Z��A>��x�K�3�O����O,�%�J�������E"��D&j�׌�����9TD��%<i� �)"#x͆
b����RɅ��3"	�8B0RA�]|��r|��⠸�w���+�?:���B�J�f����0�%��c4�QL?{�Z����W8�+:�d�L����(J�(Z��I:j��S�fL�S��%}e��QTTҫ�P5�%H�5`;��Z����*Q�Y�t�e�o� ��."����x\�c�|s"���U�Dh�$f8MD�aJq@�8��4��@v@o�Q�8�ϢTMx �G'@���6�՘$P���%f�=�U�6x��`6v��ȅ�K� ��M|���2J�bR�J�;����P�xy�	g�h���ҷ㰶�1U��_�i�Ɔ�	f�ܘR Z��0�l�OH�H��2�֒�&��J�g�_A�@� .��d,M2@�$��s̖��C�$75XuIPg%��f���t蝘�0!�R���L��>�����p@B/���'J��I����	 ����8�LȬ�fJe�߼�\y�VK ,��dj#�aP��ǰ��w��5�8�8Aq��As]UL�Ƭoάż���:�R�_	fL�8�~��$5����O��B�oo.��n����>GZ�*���Rq:����#w,R2zhJ�\��.|��J�f�E��B]��y<����(��ܗ��\]�x�t]_������ќ�D5�ݪ;gd	E���&w[�2!����m�[�V%r�2�����c����D��&�\(H��>U�-}���?w��~�ž_������K��i������� j��Z�d�]��M񔳏� t�Ho��;�7y�b^�^���F��dz8�[�P��uܰ,����S��'t_�Q��L3F��dz�+ɷP˜G��ml�ax��y����_�������z�E��X�z��c\�z 	R�n��
?h��08��<u4�.{�M�v2eH����O�����1k� ��T�5� �@�߉��&K/���+C���i׈����6X�z���G�q�\�m|i���Ç�hu��Ct�T:�q���l�c{���z�T��%�ʤd����h����)�ύ��Og �*��S��ب��3	�Z�%#e]]����ĂJ�Vn W� �5���թ���(W�Z�
�
ꙇ��Uf�YM@2�^�ȶ�T�k�-��i*W�~�ن�����8��(NOFǵ���M�Gx�f��C�:�v�����9�J����Do$��4�][Կ�	nג�B�s)@��8'Y�3Pn#voO:t/�d��`�`\��u�Vg��F�T��I�JE���$��y	�Q�yS��E�b�Jm�T�҇���@9��Tٳx^t�?窬}�Lo+��S�R����'�h�E�_;�ݹ�U��ϒ�dl��ݾ{q�"�������3�WTp\��F3��Bg)����R��F��fݠ��>X�M|��� �YT��5���z]���@\�����
��l��a�.E5?F�[��^�4u�[.������
�+j��_)�R01�YJ�\���8��]�!�i4Y�˙�M���W˻j���|��rr�7:m�ø��ay�K����ᥱ�DU�HH5l�_w6�T|��A�q~��V��ut!�ˋn�̒;��I$!bP:deQ'Э�9v�-^v��B��g���xd��#���e�������j$�G�y�:��;�?7�ٹ���Q�H~H[� ���$�B����
�<��ׅ���xN<���iN��	9и�I)S[�tA�K;�	��Z�aU��[�fR�f�H��+��1�QX�$�&��E���ڮV�`�����0��æ����Os�L8��yo��_�7������j����;�ݑ?鎸��t8�g��^0�cOǹ����F�X�θ�\T�E6nRa�U5ú��*ˢ�I��/��1��E�� '���ў��n�
�h`������Cn�qaJŶ�-�8��%�����<��Xiѱt�6�<|m��\gm�ey��;���e�YE�Ʃ�;��\e?�1w��7���$e=k�~�@7J,*��NQ�v���זSXܵN�[�9�
/6n��|a=gW�l��0B̀������;��n"�"+0��P �-J_�\Wi�Vi�Vi�Vi�Vi�V�H����t �  