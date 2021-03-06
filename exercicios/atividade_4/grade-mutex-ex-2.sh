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
� �`�[ �=S�Ȓ��?�`kl~e~&˂�����ޅ�JHc��-y%����\����_W�	�Ů{~H3��B�ڷ�*���������iI	��������Ղ����m?�h���U{mm}���Z[������Wd�˱�]�8q"B�r�����ͪ��^I:�I�/�w�������+?�������'Gc��?������H��X(����??�r�+N<���uڕ����Nwa��{��𬻰��G���땗���w;�?t6*�>���,������ +�Z	&�a�F�'~@j1��,0�V�xa��xH�,0�p;�In���b@�u�U�0��Oj%��5� Qw��qǟ�qE�$�G4�$B�1������c2�q8q����*43���/.�<�iBۄ܊q��gx�JJI�QE� ��в��lq�d"gh��	ic��J�'��
Z9���$�#]��!tl��g������O��Q.u�W^������gh�����
θ7��(`
W%oss�G?����0="�G�I�7��蟂CE_��O�w��aR�i��A�:v.�Yhq.�B�&��d��H���pF�@�-�����n�_�?	\��&M7$�f�� �]����}�]�]F`E�����~;??��ުBVqʻ�L�Oڤ�m��:Z۶82�+�1��dl��������P�Iإ�eI"E�������,� ��*g�nQ�	�Y󦄲7�t6�PV����T�r�Ӂ����uە�/�'�V挪�V�Ig�Y@8҅��a�W[�jjMe^^Ӏax���!K UM��.�U�*���tV !�ۅ�2�H6tZu�X9ȋ�)�rq��d�)��2��mh�s�ـ�����>9�>[^�W�Q��Z|�V^��(i�"b��S�$!q�Lr
���*Lu�g�6�8����� P�b@�쑯���Vke��k�J�5CQ�̶��+��W����$��i���Ah���\_/��776�����������G�Ķ�9���9;:��z�g��w������<T�0y�!*�~�'`��'�].��2��"�]���Ʌ�~R��8Q���gu*W�����Fᇚ�RE_�>xgcfek^8� o�n �$&n
�Hp�&q����ب6	r2	b�2 �3!`a��6	ǵz�r�T+�4��Z��K�\_�Vk��w�ƌ����l�k�i�?ƥM]?�g��4J�2�_��e�п(��2�|W/�Q�T�F�S5�c?��;��$�M��QY0��{�$�����h�$^�r��W���;�}'`>�{��/G�ۣpL���ц��(�ùl�����x����V5���qc�	��[��:���C�6�K
�$��R-��YF���qQ�%�߬��@��Cϖ��_^�'�9l*d��R�:�j�7F��U�[�0�jy4
�� ���X����WUH�An�!��GZ��7pW��4E32�����R��.�T��T,������
���:)\��M�5�~U<��"1�F�����AZX�m
���ؒ���5�Ξ��Jig�_J���0�i���u��>8��ON�	�0=�IG��PX,q
5���8E��q��Q0nPn�BB�4-iC��p�F�4�o�\�|}|��_}��Y#n�Då�R;���Ha�M6P&��pj���6�o��h� ���|���)*�t[X��%�e"W�����p�j���WҞ��� y�7l�pvw�()�-��0��u���o�<�{$S���dPun��P�YdE��C�\0� C�/�y/�c�hî��,��1�
�y4҅E
Ǎ�b>n��-;�|�$�.|l�d\�(H��&S�e�������p�Aa���U�ݩ�,�a3��VU7�I�D� 롒�ᵰ^3:��ٰ��ɕ�mpkqs��	(���n����Q��­��M]��,c�P�G�3���x1jK]�7U�`j�Dj��f�֍:�ؘ��`y��2���U��И��_m�����k�O��ǸL��k.��� f��cw@=��"K1��S�M�e�<;=`��8����g�W����<2p"j��e�Ծ��;�}V=jKX\�Q}��"�q��͕Ft輧�ebX�3��V���[y�C۷�Ҙ�;di���7�P�yfa&o���E��>z5�ch-H��H����	ͤ]"�E�5���:�2�N%�����2ʮ�;�6�6��Ubn8[�!�NL�.j�^�Glb)�r	����0*L	!�%c��̝�S��/O��.�y��g��ib�糔��Ȕ�R����lR?]_�2��q2�e�����Иy���^��kO�?�re������d�+F�M0\�wH�"���+ŀ1W4	��d�L�����+�샽�B�-u�����h6�#g�]�-�W������PŢ���<����Ӟ���q�p��o�}|t����k��>��uW[�oZ9(6�Ea���}��6�(����7���t��(�)�?>�����W��������j�y`aQ������;OМ��aX84?	�UY�WA����U9%�4΄�Nn�^�DCj9`RV?�l�Ύ,��d��틍�I���X5�b'���4��u��I}#1�>�x0��sv�� �N��6q/$=�6S<�$^xL%��l�ʤY���ɩ�"ɪ��O��:�hQA8�E�8��P�#ˌ�W�KB@b*�SFH�e��/5~8+$��ҁ�F��O���yD��TSB���"4c�X�����n�6����_1O�����&�g��_]�l���'���)�&�X����ӈd��%����#g\��e����Fr�ؙb�T,,�-��ğz�NZ��vD�I�W4+E�n8	^(�>��c<^*�KO��j��l&0�#�C�iRr�4@�S�Y~�Y�S�q$��:�\r!���~��RH�A0U��/s���F�##=ӏ��z�����g�0X��;��ӆ��ؠ�����	`��[Z��$���8s���y�a$p��b�|��r	>���Dՙ�?�3,Noς�\{�2��M�N�,�>�
��D	K�_՘�H�Z�4oꖆ�&j��@� 
�,��] c$B�/�q�#ϊ�^���?�E�Ċ���KKx��6�(��u�IQ�~�����띞��koO�b�G���l�F	�?f���ĥ�pD����YL����%�@X���?��|��bބq7]��#����l��b�#vιY�6���O���ӝ�z{d�x�h����H�J��"m��M�H��0X,'!/Asd��eҀi�`�U��Bl�bn��N�V�����0W����Ei��C�R0�0vG'L;��I
Z�U�&� N\�DI�@|��\��Io�����O=KӼ[qyS��Xp�(���={������$
/ hH����N��2](�.���U6jq�R��6�6�Pt�>�jee/$ה�?�%7�����E�3����[,:�KK�yݶ,��S�	���}�о��x�B���X�*�X��r�T.
L����$��-�c2�"m�F39!�]lw@ӌPn(�ɭ�+m���L����l����Q��bצ3�'� ��Y(�"�	Q'N�q�[(O?�W�E��dV��a!φ,���P8WR���d�+�8��m����-��.� /�c���{�}Q�r�i��u^��A&b���L�	��g�xo&��2q��ң�*�`�w�L3�0�p�{�9���E�0u1e�����M����D�2�L� �g�įOo.mb�sWL��sX�Q"�;n�NY��Ǩİ�X���	�^�s.Z��B�lTG��B�`����D/�|�[-�u'I�N��%���J5͒K�C�؅��s�3P�!�uV����Rw19)��5Ld�[P��-_Y�2B���Y��\�i|4}ü$�*�H"cR�Z���[��,D�kq���Y�X]٤f���ܳt=t���R�3f��aF�"��T����Tf�{(;ـ�mҖ���>g��{7��7-��O_�x2��,n	�F�ڎ!b�qT$�0��~|Q��C ?�����N9�,��Q���-	0$��&��WY�z��y&�����f�%0c���]�1�>p!��%�6�y����.��Dy&���/�#���y}p�E��[e� ,�P���iGF�t[@U�Z��-��4�2��UlW�2����)S�L�
�E��i���S6�����������8��gc�БX� \�\��V��@�Ge0[�Vh����P�6�R��lU��-j�4n�S�Cua�8��WD�jʜa�..���
q�f�a�f�V�;{0�1{yK{����=�����)�	ٞ5�U���	�9>M�G$� 2����$��+'.Y4�ʹj#ǩ����2�Q����,(�&=1�?�hx���R5�i%�
'�7��b6�
�GE����O���5�<�?�&��R]�>�e���c�u�8�3m��#�{��@��^N���x��1GRt��8���>�(�}�(r,� ���1���3�t�&�Qx�(Ft��m��.��4f2�.z n��B���>���\Ćf�U﹖n�h��^{a�/;Y&�����ޭ6�#�IHUH3����Bu}���i�/�l�b�Y2sg؝�,�k����ִi/f��]��m��r2��1���p0�a�ǉj�.o��X�8�),�Ϟ��]� ]��5��i���Er�=���sf���Y�݃И��G�]x�k}���o�r��8��?��9.D��˛���	��&��NzvJ����0i�<��Vg'�����j	5�i!^��œ9 ���ROA���F�� ~|�C/L�ș$��:�79�P�R��7@��jX�dnF�v��f�|SNX�����[��{a`�d{���_�=�g�g'��Y�\ǶzW!�l�Z��	�܉) �uS�<�ʬ��p�r܄�<Z�v�d5�eo�����?�5��?��_�W7�Y�|z�ˣ\S�0���.d�oke�)�jJ�hK���|ϐ��rF�� ]h��B�~/�3�|�;	�L�ἵQ�3s��������D������*�d�L󎴺����ְ�B���0o+�8[�:ڻ9�V���F!�����6�;IT��=���9>O���_9�,c]�i��r⬉����.Cq.�7/_� q�=��Vr�Ń.��;Ur�����B�|��$�3�,�N_猿��&	gJ��2oYzf��,/pU޹w�X�&!�bq1?OTvg�"^+`rh3v��A���ɀF�:��3r>��sE	Gf$��?�����B�-�L���LLp]ޖʜ���\�x!~�W�iovL���ML%i*@a�c�}�Mŀ��	
���N��$5>����2�htȥ%>��O�6��>1'�~��Bњ��B���Y�S��EA��I~����w����B�O��zf|���*����O�?ʥ~�-�b~Q��~d�%��0}�}�0S	�#������yGyc��������8
/#g���ob��<�G�����G�7�Z �ޢ�o��K�����&~�z�O�T�1�Ȳ�:ח�dy@r|2v $���Ї��a�=����f����C��#;�[2R�����".C�O�`7&d�V���E��U�F&E�ɯ��%�$������"�󆬶Y�_�ܒ컭�C���U��m�W*��)S@�o��`���3^�I��1J�0q���?ӕ醜-Oc��������o�����c\�/v^�v�;?�|�4�Z�ُ��O ��:��8��ݠW�����T�z/�{�]�(���7�����itEG�P��1��:�o�:ѯ�
�K<:��P`I`�L���h*)�$!���s$	��`ۖ�	e��.0�<C�yi��2�K��b~c�}XL���`_��2�w�>��8�y����hB<�FΧ��'�-tO��ƽ�g��O��z:����ih� I�[++�����wl�m�g�+ƆH�DY�Y���4�z��^'�b�E�*")���c���������3�P#��v� �Mr�\Μ�\��~i̈́���`/�~�����}�,Ҿ�\�ԟ�g>j�ɥ�WoP��_�������ؤ�����	Ő��ˡ͈�U�94��2?�C\���x��D������PP�g!h� :P}����
WNJ_j��z5P����OrB$�֐�����K�{E���6�[���
1l4�!nτ1���-��۠�}}q����ǎ����=��,�"/'��A�EG^
�}����T�1U�#���=;�>blH<��M縜�x.�c�
�y̲4K +f�A�	�6Gӣ�D�x����3��(�W��w���o�5�j�Z����`>�5�y%�%~���y����X�8�K�:l��8������m��/ϯ:b�K�;R*pܚ�46N��Иe*�N6#�	�q<���إ�I}Qލ丫W �l�O}����=���"�Z0v#J�7�����p�o#��&j=��������9����������Q{͊4�B���r!-��؎�"�f�H[ٴB��A�w�36���]�g!��s�D�OV���"��8ͫ�g^K�8#D1����@����E�;�%��y���(@PzGЂ��OND?�����%��kH��o��+�2x�aŇy4����GP4�%H�=`�~�d����Vˢ�
fo�i�3�,v[���S��s9/"<N�g7R��_Z8�_�Ƅv��b5[H��X�2��x ���)�Ed������ᛴ��Gφp�)�{�u�$����W���_�u���y�1KAW{��4 ��; ��!���$
��� kF��U�)�1ς�/AO@���aȽ]ɷ�f �y�MnX8 ��Q!��N��G����Rc���(^�\W�H��aWF�=��9�R�B���'Ps�x�2�+��%�F�_@�.�W����V]N���X
�8��zǗ()$20-��bም�s�����q?�HUM�9�aD �~�����?_�*e�{�Qt�o��Iυ-���V�6^N��9�!��]G4?'��6�Q}q�A����Ӱ	L���nZw��tq30��?ڬ��I����.�m��u�+x}k�ߟ6��q��G}\�X& :�]q ?;���-gD]��@���]np��d���K��E��@�`��I�u�~��2X�8�@�})�>�z"�L�z7�ʹV��6�Վ�)�r�l�x�-y�]V&�.�`��>8����҈�,=w,�{� |�gQt��܀.�K��|����%�\��f�M�������y'}��ؔC���� :�
���(W��\Gt��BA��i�����Ճ�w��*�6!�Q�I/�B���~N�4J�yh��)�Ǔ�">�#�G^]��0U�ț��5�l�]oFW�Ȫu=Z��K�f�
U����*\�Y��݊�ǲ��s�\K��ֱh9��e�mQ�ȐV��N�Q�#�O���u"K���W[*��`�`XW����b�#�C��H�ڝ��@�G���G9ꪓ'[�[%ci�
��h^{L��(�!ܪG����~U`�o��V�Z{$������-Z�q9�wZ=�3s������%����H�{r�S�z�L�B& �'fS��Z�>d����㣐b�������sԆ ,C�Q�4��Z��BZi�J�j�`rr���`�5�ym����8A�]-�eq��@8���ac$Um�p���\��nz%u�- d`��վ�4��-�)@w��-�(���r��hLL-����h!_�lkŰTi��h�q��e�݃�^�A0b.��g紅�S��f�q����Yɭ�P>����4K	`<^�8�s�.�V��,����e�9L�N�=���	wA�;U003����v�sh���@�����ʅ�7�T��4S�ϕ8�%��d�΀���F�AC�(�7��!YTR��'��źԬ�U��>���*�����f�>i�������O��'��o�K�~t������HY���猂�=0��nWh����I���[]����%
�a��/T�2����n�$�N~�����57�.=̵��N{;��	��`f];�@ıs�������񫦾���ή�8�|���u��	<@%����%M�4���2'+!Y����A�O4?��0�P��U�i��h��w
�l���<Z3ߺjk1��2&��@��Jx�B�������܉��|"ڊ�Q�W�C���P���6H�����-�2��cc	̈�:G��3G��]�̞���5F�����6ir&��<��#\]��i&��з�XJ��`�� "�q���_�`]��g�X�0���{����1� H��q�V���;��Ι���qX8L"�ʹ)���<��j��ا�;w�X
5Q��n�U���a�@��?b���Z�#<6ꔳ�W}�7�d���8�	���B�FLI�ih�Q�.�[��]ŝ<���-�]i	}�5R�2�y�s�Ü���hT�e�Uap�C̀��q6���5�?�I%�vMH����p���b��"������ϗ't�NKm���o'�ofߝ�n^Q�Q��Ҥ��*s��Ԥ&5�IMjR��Ԥ&5�IMjR��Ԥ&5�IMjR��Ԥ&5�IM��H��SeK �  