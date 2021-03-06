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
� �J�[ �<�r�F�y�W��K@�w��-�Jd��5�I�D'ٲ�(h��p.�-�>&5S�U��5�?���=��4@��ǩ�1*1��ӧϽO��� ���>m~�]-���]����-�_ߴ77��[[������l�6�!�?���P�	�F��{3������&�]�
�+�t�ov�����\y�O|͠��?���������iCZ����׿��W5/L�y�����ao�]:���{������`�[��?����eou����?|��Co�[B�!u��W��2��_I�4�uӉ,�4v}b�!�J@!�ge�n�����#�lfx�R�G���%�O����:�d��2��S� "�O]R>q������EBӦn�<�k��[3��s#�m4eVH+�?&x��D��&�A�Ǥ�8��@�$���5Y��ʄ�����IE�м7C�F����$��Z�X���S�m�O��9ll��w6g���㭯��E.��K/O������@le��SB�{K�`�	\���|���3!̎ؑ�`{-��I8d��ь)5.4�j&�����omBw�j�S���XL�|DV��d��]��C�u`���=�7�9��p7��4���а��NH��(����_��ު2�!���S6���~eee��S:��:S�6�;�8���Ѷ]i��X��i������Mj������n�+�x�Y����yug\H �I�3P�d�v���������x�@Y�!�T�m�8g��^�z�R���^+]�ʫߗEHg�"��23lp������Bm��g�73��$d7�r�̈́{Oy�,W�\�N�!�ۛa�	&&#;W�� ��b"FCJ�\_�l�9%<,[�x� ��n`z����M'�w�Fg��\#l��r�{iy�;pM��֌+"�1��$t�����1�����{y��8�UE� �V ��}�m�|�h���ɷ�2���Riyd�׸���Z�LC]���5��e\�om�]�;[���������k�;U�q���p4<UG���������JUK+�m��·(���nE�������tOjä[ ��ؕ��^��c�
D5@�T�$1��n��5�,����A)쌃b�؆dV��,�*�]�j� � �f��b������A!J'�P <�C�������w���TEc���	̉�,E5w��)9� �`ɂ�����A���:��	ۇ\k���\��������i(���bo����2uʞ�"Vp\���E�?�ԷU`�Fd;p4�)W(;C�n*AUA�j�ٞEcR�[:���
cU-y���s�p�G��OM��T�����_���jeӌm�i~@�O(��M��`j��J�����S�r�������PPH8٬��u��չ����Z�a���_�,s,^�۰����������K\���t�+�����6X&`c�o3,�"�F}�ɡ��Yٶ�1at����in䇠�q'�Z.�X˘��&�'�!�^����MWB�6uD�钐��X�~��������!�F�#R1DB�F��`���TY��F<Q��*E(`���рa�?��9�g�������㳹�Wp�Hr��©;�XLsD �T6q��p���,�'�����y�ȢA�y|��KG�,.W�U)��Q�=�M},�]H <�oNN*�x�Ζ��&����]6�!��<g�ae�H�9��Q'� j�d��]ȅ9�j�#=�kШ`�����_�A�� �ѳfHN�\Ы{�Z#�X(-�P�fy�1��zX�*[�I�u=��fck=Յ�$��gL�G8T� /�]_)�-\'wf�|.�k�+$ 8� 7ǲC�󲬲�V�]y-��K,������Z�j�e�"���>�(ˬ�I�VQ���i;?!�"�`�nw*�0 [`���Q�be�o,,��;�";�������)	\|��n�U�OQy �.�6���{�D��2��|�/6��T�	a)h'i�]�m�Tc=8����7W��]���8t$��;��[Ro��G=��;�[�?c�
��b�P%�l�7ک7��G���X�9'|����6�oe�1� o5(9Z�u�+8��qN��B� S�$lF�؊�)ؼ�c�p4��Iv��;VP���A-��|~L��p5�@�o��9�B�`ʄ0"2��Ȧө�0z���^aIW��
���N$ĐYd����PsS��9��X�\�XE� ۵�&���x!E��b��T�Ĕ�ZT �H�;2X��֬���5|����q9��0����)�-��I��W�ZK[���i�����s��t���	F9`����`8�j���F'U��G�ӝrv�	��g(���qoDH^� 
��VP��Fx��J���A}�?	��/LA{$���\`H�� ��T��곓�,GȮ����꤃�b�m�\�a���qD�T�g纓����������<%o �Tq6�'d�gp���r��Hja4��z�>b�S�H�O����ˊl41�OG/���?y� �@��
��_@�O8�l�?zs�Cw"��t5\4^ŉ[��iM]�0����)�Q@֌i~����<A���ʹ�����Q�i�T�$`�x�\c;��?Q����k�X��U���.�\�PG�~��$��P89�f��G&���SeI0Yn*���R@�Ks��{i�{t(�q,Wͻ�'Z#��ʅ8C^�&��ƽ���[��^�m��1���^�(�J�X,���s���7�O�5��46717jt�5��ho�S���)�uZOjd������n�����m������F� ����-�=�v��d���f�����om��~�n��]�����{�픛M�Yo�)z8��a��+�F���9N@��RQ��Y!��j��Ѯ'I����V5����c`�ll =yJ�[�\�
=M.���x0r ܞ{�d�C�����c��h4��vF�!��/��Tq�y�r�$�3SDTv��0s� B1Uv� 	��h+N~�I��8��M����<�a'���Y"�휧��L�*�Wy@t���h.�}S�	��
�%��`5'y��_��c^���h�,�>V&��������'��>����2�L<ND-����KUV�z��JT2z���vcIzl��6�:���/�1�5\C�ث原e&P"�d�0��m�7���%�����\���Y���\	�Lm�`��Im��*0�h�c������_�`Y>�����N���?�����z��%��#��G�;&�_�Z|�[t�l��K�]�[z=��8���5K�,͇ܓ/e��  �|��yeI�C�����d-!��ݛ@�������#/�RUP���[Z5���JWŇk�E5v��'Ԯ%�&sD��TV<_��1bH�,�Z��&6��'6i@��.9�%��i�2���fU�n\b~m�r�)��K�,��#�Q�|�	GL��۵�\F�����&x�8ޫoL�UeV E�!7�!q;�޸:�2}{%5^��ܥUg�����U��
�(��@ΒD�Op9O$ ۧ���}�Q�,K;�����ݥJ*T"҄�P���E�T���`����/)�Ȩ���=��7_X,|���nwI��<�i�o�{,��x*�/$�f)Nl���AIǶ�Xދ�r��
��J�����{@hf�w��
r������4��/����}o�ⓠ��%]#�������U'�c�
xL�+�{�4�6�P��B�/�������Z��2����F��۰PU��q���!م�^H�(n���f�;2����Ų��\�$��@`�����:j�]��"���?�x��+/kY�"v���HR�3��B)d���_�qO�J������vIv{/q{���L؝������n/������F;Bt�+^*ú��`?���/����p��
��d��B-E��6�^�#N�L�lN�#�GD&�g���� �/
�Ω��ck9���ʵ��lwao����X���0_E���aȗ��Pe.
]v�Q�M�*n0%�o ���I_���-OZ�T`,�cE=;P'�Ã�����L�������OM��������ᚚ�*M�h0R_��\#m������9�@O�x�L�L`������ˏݙ���8��P73�)�1��{��*}_Cd�[#S��D��;�ɨ�.��ק��i���P؝�����YcIKi?R?���+�����&jP䥫Y;dm���6Y|T�1�s�x� ^�P�f�r+��%!�mc���3�kA
�k����;m" �.@�Ҡ�h���x �B�)T<+i�7�_\������q����<&)D3��b��0Q�R�Za:s�#�l�����{�{6^T'	j.��a%��]����@�i�S�&�H<`�׸��"�ԧNH����|�r{��C[�@�?j�af���Y`����j��q���W��S���Bc=A���5{d+M6�����ľ��a��:̓���x�YK���LK�0�3�a�b��dp������wP�5%����ču!�>�D .���ҹ�<�y`�A46u-�A8ך���Am34�,.!aȌD�����W��S���x�̘���W�L����%c����W���r/�ج�=�3�L>�g�4�^�p���i#�<��^K����������|�K��K����B=���$)>��}���pb�]�E	
í���ٯ��ɛQ�g-6ⒾU�cK+������yftK}���,�Ǻ��l�g�3�X��ik%�#�aZ�nn�Q%�����/�!�%��.>�gZ�w�͊G� t�jٍ�~[*R���s<�!s�c#";Jy��O/ş�� ��z���D��[6ߕ�Xl�,���������>,�Q�M\B�Į��O	����ml����n��o������_�:xq���W��~��o����Ó����l8����g�7����OZO����o�H���n{�>!�a���ǁ{w��4��!7/g'-eCC���9tZ`��G��Y����#|�kj3��5����kn��Kd^��7tH̀���$y�i�S�§uȫ~�(��ĭ1%vdh5����a��&"���OT"X��]��yך�S�>fjv�" S�$ 
�}yp�HGܰ)���	F�l@f	r�`N��l���S�V%�a����2�������0�9b��������l"=[3��(Aáa��𸿩ך�S��E�[�s��	u`��q�	*9�{=� ^���9��_��ȴ��j�12��t͡@3�1��+�����oQ��K�%nag�U��o@�ց��8
��_�K3R鍅Zn(2?�5'`�$�ZC���.����`
��N���[�<q�1��O�k�y����_O�k�Qw�+��-XÆ��r��xZDAHրj>�Z���@:̩Y짣?��K�X���!�k�� �a�]P�8@I�gj��p3�u���aEB�*��ɫ���wpy6[��<�ޟ��Ԁ�(�ض� [b�W�,�*��6�
��>r����V� ��V�[Sr���ܙ��u�r��3
ظ5x
���;R�,�OqOB�mG(.n���6Ѹg�n�����r�~	����@�A�V�F�x����im�g�W,�"A�'����!�Z��$�*�(�Ç��詷^���ެ>M!��w�,�vv�͛�z�֒(��r���|ne�E&�hH�Ap7J��5�%bＣ�m����*ra��vTP���f4�ps<���Ӝz�������^C���C�z���m�˲��x[֓�U�$5�(3'��Z�v�9�^6���n����pYf����b���/m����9���l����N����0���,��ǅ��hN�0��_0bj�eq�����8Dj.�v�3W���n�rn��s���$'��T�R��P�0�)i�����v۲L
�뇲q��K�jNW��k~��9���.t��o��s�H�E��D�(�5����n�!�w�򘋔1{�ҍ��ڭ"t��G R�
��᫱�o,J+�YKi���<˛>Zg*Stlw��� �z�����qD��9���=y�_�����r�B���6��Z��=̉�܃�f��&�E�0�O�4b��!6��<K�.=�Hd'l/�r3�J�5o8�i��Ѷ5���]���4qkFP�/�w��^o�X�'��3�(��%��v�hbZ/.Z�t�1�=�GN��8�k��e�<rr�4��?��#k���p�	��E��f�
���TV(
�B�P(
�B�P(
�B�x�"�� x  