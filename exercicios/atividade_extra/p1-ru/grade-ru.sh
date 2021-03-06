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

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
� ��[ �<�v۸����`�4#9vb;_m3�L��mΤI7qn��fu����%�$7���������>¼���H���4�={nyf�A�(��~�����&���M�mmo6�_Y��׷ַZ[[����Fs���v$�e�nH�wL?{Q1ܼ��OK����H���}s����������Ƶ����Ǽ�������f���4��/>���]z�ڥ�*o:K��A����YjW�OΏ{��u��str����Qy��<������YA�!�T�dm����$Y�Ok�l<���x��ɒ����i�AP!$S:%K�gx�F��@�M0 �ː�+���oH�@����h�� ����':&�7��,�Mi����L\/"�	��~���Z�fFZ��%�9��M#������8���$��4\���-O9��]������Ť�c�*C��
�hV����?t٘�����!cs�{=����6~���R��_yy�w�uN�{�����vW�{��0�����Z{�E��_&G�h:�A�ƴ���P��R:�t��0)�4�E��G�}F���J'@Ģ#��h6��L�`�����{�����Xn@_e8����������&�����c稳d]��E�(�꯿���ѣ�ֳ*��K��4��E�g�8�� �m���ؘ�i<}����������dYv�e۲�<	����E��<� �'��@ݜN%&|͚7$����8���(���U�M�N��T޾��uZ��7��fj��K�V�Jg�YB8ҁ��a�ی,���ZW�׀�5`�$x?d���	_=�%�jW��:YA��nn��1����F���X���R���G��┌	`���:�ʽ��ل�?����C��x�=�P���M�櫴��,M��fn)"�!L1�8 �`��"��C����\[aÒ%~ �V�]�S��a��\[��ɮ�]MQT*�5�FI��'w��8I���^�@#��"������������=�#o��8�����z'�N�{�{�=��r��#x���-��<���x��(����hW�C�k�� ݕ��_:���h5P@���H"z�N�S�t���/��T����}���L�Z�`v	֜= �n�|}k�C���D�Q�YP_��~�6 ���뭢8�^�q�0�8��yW>h�Ua�`je�#����0�����;��N�'l2��w�=Pʙڳ×Ǥm�v/L���/�N��7R�s4���=	#f( WcFQ�O1'�NT9��	�\1�5}��U��u"w2SI��-&��A[@UOG<B��ч3�鏼1�Uc�֋ãn�NP�jv٠ٰ���#ު��֭�����+�6�N��&��/F������ͪ�|Q ^�Z�P���~X�oV���^�(�����u����a��G�L��ۍ`��z�	ؘg�c�R��a�gС�u�z�����^7q�Q��h��V[5z�UtG�O����y}��������#b핂<�z�8�D����3wt���T�F����l�XݐZ˪aX��I�6���go����+h�kz~,��O��
[?�}#�0j�BرK6�@@9��}v�26��,b����Q?t4_4��B��8f~��\�U%�2�({���5�� LA�99)�d����4&�ᦝʍ�F��j��k����#S��2�f>�F�$ _�/��LI���1�h���,�Eb\6Y!-�_�H�����x۟~� k��$Pn̡�k�|e���a�l�'�B�u7kÆ� p����v엿�!6<�2��AhU���<�/�X�<B� ��X��j��U��|�>�0�"��T�`�C��[3�@]���e7��0�y�s=�$�aH!����	����~��<��` � �U	���r�t����J:��4�3)67��c�acJ�b�����$��dR��S�GN��(��G��1Ū:6HKA�IU?��ͪ�� NzkkT��
��; p�J���\���^�4Z�a�����IY��ź�'\U�&+��V�����h$�!��c~�����{�7 ��`�#*�ueTBq(
�(��| lf3Z��Y4B��7��TG�$�I��-Zް����[+5��E�N�E9Fk����1x����]&��h@���b@�Ūy�n	�W�!N$ؠ��aШj���0g&Yr�s��W0�z�J฾P4Í�₈��2��#��O�ւ�i�5�Y��1>�7�G���}9��sV���`X)~B/u��qZ3���E�J��}���;s�h�0�>3�O�Oz'Ǉ�uDة�Ig����N>f!}V�MN���C�`t~p-T�A� �o-�X�?90%dlq���O�@�7�C�Ig�\�!��65��F�3�au)�t�:�~��m�CT��
[��L�V�ũn���Q'���YA��OɊ �%e���I�񌮳�� geZ�q:�(r`lP�H���W{�/mUh$����� �s H��&5������z�g�t����NWu`S?X̎[��7�q�����OMa�n<���A��o(ܿ��'�&W#�N���Ģ\œ���r�J9��?�����kh^�ֻ�p�q@�A^����?��;0��a^%��ɾ��8B�#tE�9�d9������Vj��yiJ2q(��N��_�F�;�3�31G�m�k���!3���������nӤz�#,�͇AN���A�z���z��۫�����[u���چ���'O�O���N6V��l��f��?��������6V�m X_}��ğ'�m��~��~���֓-���Zrs�)��l�N��h'��N��
tǞ����>��Q��*a�Sĺ���](�j6�:�l8$��8�M�X����CVV��3�R�޻�5�M{4X9��ipmi��� � N�l�1��8Xc�l��Q{�2k��b����8�IY�l@��_h=7 Q
 &��~9�J Vԙ���?�����;�e~�i�b�Bę5}߾H9=��ԚN�tk��H?�ܐ`CP��F�M��
qR-�L�Su�i�o�=��IÏj�jUj���պP��F2M'�V��d��Sfc4Gq$lm��a�nHl�D5/`���_5|��ᴞ9|V���%K�1Ml��Eq��1M�1F*[j(@R	�bp�-%$2�1���ԡjAk��c����?��oz�u?g�s�ַ�ֳ���?�K1�%ǄE�_@��8U��(;:L�%��3��j�^�Ύ�A�4� ���&���稘2�ԡ���WԹ��Gx����š���	����������i�6�c�3�&r�'���kFNa���	����9�+��iF�2|�5���+P$z�c��6C�9T�¦���QP5�Nq�2�v��ڋ�ϡHYq'7�7*B!'�~F2����g�@T��DHl~	hGAU"bک>`��B�qY;���Ym]����:h�e����$�|;Af�K���y,?�]�����q�2BcԎ;rR���a���y��3:�-�\N�vD��d9Dؼ6��!� ;�F�p��p���[��b}�KH�-`�Mِ����dH��'�}&紐9�_s{s#��mn����GI��M�y{���#ӡ��oL�Z�*��`H�2fVe��`�80Շ_�Zv�'�N�1"��-��&��&O��Jn���Ag��F���x�%+b���Нv�<ۀ����ގU,:���㜟u�w'o���ߞ�����;g�9;9?��v����ӣ|�y�#��ݚ�l����o����v;�����{���M��iw�p���gٶ�!�X���a�<!������G3��*���+0�i�g�W��J��P��S�Xk��@���ʖ�N��-�ˤQ�Ba��x�4v@�1c�҉m�G�jnxU[�ȵ��jk�@��1��`=а|;�(��XE}����O�
1E�Y<���\굡TquOO�t/1}��B� ~h֑TADP�!� QLݱ�K�	[	e ��NQGBl�P߉#7�)=���ğ#L�t=B@dX�O�R��( B3� ��)*�6᭘Q�����xu+<K���YK����a�����cE��+t�Rf�����<���n�r�������=���Kb��w�d����Y$�ύ�ѩ��]�w��j��2���D�`vJ�����^PK��uH�ܼ�	iF�'�֢�
�~0�E�Ե�Վ1_JX�8*̫Cܪ�-dZ^�n����^:1rQ����.F�P��� ���%�,R;�;>�qE�D3�w/��h�`�K����6:)��C��G�ŉ!�����ٝm����OH#����}�."�$�G�T���������&c��Kf��n���#g�X6�p+mY�ej�M}*w�L�@�k�N�?Z���U�l7񃻷�q��!����E�U�IϹ��	���X,2RÐ�~�F#7� ,�*�kFͤ�����5�B�I�F#�,V"@u*���j�����-<��Iַ�&���ig. �� ������ŉń�/bY&�\�5�WT�I)H����f�0~�+Z'��-�D�_')������4�X��644ؑ�`����a�QH�y�"�@(�}4��U]f.���ccW2�<'^�M�f�Uw�7�{�;=���@�F7�xk�C�v��(�?�C��lLꣀ}r��b����c����뿹u����A��J���|A�H���&�
}�º�K�NNgtF ����G]��M�DyI���3J�.<H�0ݎ�LW W	���T��̥���?�A}F��g��������|ݶ��EL�]��0���.���uIT�̥�/�:�yˢ�'�'����98d�<4�.�\���i��5��<©���`�4ɼs+#G�	�\������N�	w��/|���C.@l��"D���E�
���7��i�E�e�u�\7x�
p*�xYj2����ٞO���g���I�QyS0�HP�,���@�3���g�IX��(�i�<���H��R��UgKړ]4kQ�R��6�6j�P��jm�  ה��oP]�#ʵ�/�u��ӟL���߱�e�}F�m[x����uN�!j^{�X&��ylt�B,Lz9q��&����DQ�Q��́�+�m�)����D���"�����/�Af�AX�� t�;��7x|b��z��D
-s�g�6�F%4Ӊ<�p�#�ܪ�}���Oڹ�"�y�ʵǼ�,r��	�2�|B�M6q���a��0�J�k�I0��k+7�8��^10/N��*J:J�/�ըc:��K|)E���^��p���p�u9X���Y�p�݃�OE;EUS#�����ͼ�/�n��:���	�^���#����`��D��c�5 �b�z�͂�z��94�[~���B|��nt]��\+�^駟��wȕg3��A�\>���)��u��Y$
��xɌ�s�,q�U�����#��g�����Uat�V	���ï9�o=h����8��P@~���Y-���!��qys�Ut8y�P�P�ԉ��ԥ6����:s�p��&)�q~o�YP��(�I��m`'�=*��%��Z�,��J!x�t��_��+������I�b�6dl+�P)�f��2�#e.�5��2WH�zcJ�'kđV�}d�IM��Xȴ����f\I��D!RL5S�k6�[�`m=�c's�C�GR��q��[f��1-,�s1�r�L�!�.̎�)�<x�z��%1���m
%8J��,�9�T�<���T��(۵t�o�H�gi�d����;�.t�Y����N�M�a��ytw�%�r!���<�ueb��;�l2��-X�OXD�$�D�!#L�ah	���rk`~8f6�g *����sb��c2�T��]��a�6����D�r2�h!˙Pz�:�1-t�����I���I�쮔yr�{N�L����<��sک!ր�n���5�xS��(A�\�0���w~�|`�8�\`�GeJ�~I��UqΆp�-�[04�a��N����b#���/��	Ki��]�!�-[�%�U�I���-�,z���A 9��S�Љ� ���dB,�|�eN��ph�H����"R�g�|��,���ƅ�S�ts�a��	9/_%9�M�������=�r�Ʊ�گ�)�.��"�s��F�0%�:�8�J��Y�X��-��'W\�'�y������f����q�X\`.}�����nV�&�%��|�:�t��y
co�4!�R�U����W�Dt��;{��*J����mz?fa� �<��Q���g��Y81@I+@ �>�m�,H����tD ��d� �Yj/s�lU.�)�jA��R���M����s�꥜��q�e�x_�a�*��F�ϓk�ά�l�f~U��%)�iR�Zm����J�^��-5�t����%-���U�Wa�l�����M��go�8ȧ���}���$q��O�V���<�Z�<�
ab;�5��B����`����]5[�7n��ꈹ�[�(��;��՟���2-UI�P����Sbv��uܜ���L�2gZB�߯�5��0`��@�c�?Z��h)��K4餧�@3�_x=�{Q7���Ghv�y��w�D�Yfa�sˌ2W8���㤄��K�L�M����;�IOÛ�a0h�Y��\����D�R2=i����ť�=��^��P��}��$�#�mY�R�;�-�TJ��o�����-P"��
��=�v����v�.A����jv+x[���}���N{����ѧ��o_�h���y]����S��K�>��$�p�ʢi���PlƏ�^�i�/�ek�x%�e�
����16"	�W��p7G�S:`��?{z��mFU�g��a�>(JBN���P�Fu	�畯�k���p� ����z�����&X*Iӌ�%wݚ3T�|]��;����~!oτc�����)\��3���)�l��h���[��^/��-X?;5�v���U�Qz!��B�E8칾�r���Jc�+c]��
���.4go��gXC�A�˂A��l����_����vo����Y�Am��Un��]��fhX-�f=�Y�Ʃ���z�G��1Ht5]��FGU�J���A�;,���1_��){s*F�[���}R�G���uZ�4�ę��8h���{l�;�Ft�fqt��5�xe�����/�3 �B�q�?{�y$��mR7�����Z\g�,�(X����4�OV�F������]������u���xJ���%8>>|U�(Q�	܈�S�Ex��ouS��Y0�jA��*��u6��@0���nƽ1�`a�����tl0<�E6�"B=�!����̗Y�>S�J7�Ue���4�1"𝓇�:N(s4�wV���U�3���{V2ct���|����רO�"��0XK�O��n2�ۄ��nI��/4,�o��1F	�(���fI��q���rnѕ�U�5�������uܼ�g��3 ���=ܳ���������(}8s��W�����+��4X���6&�)��M���يM�����[�7t�,A�Th��3��H���3��u9/�S��A��fq���}K��cv����-�ʾP�v�4e�������i���U��S���Փ�����DoT�>ey�@�H�\����Z��Hl���Zw�uMK�@o�~�БR����S�H�`B����fO�4��j6u�tW4���+Y���v�I�Šb���M�6/�/��4�2X��Q"7��G�+�O�+��c����������WP囒�Ҟ�n�~����#�^䫡�2�t�;B(��q6=�&t'6�IM�W	����_��%�ۢ�7`��*W2Yw�YABm14�zL�ړ{��`��ArSy�#r��U�yh�����Z���|vwx��3'�h����Q_m�2�S�������؜s�wX.8��>���	/��W\T��N߽}�����ƶ����0�N�)�{|��C��e�E�nAI��q��o�)U��X�O���b����;c����Do6�` E�t|L�(�-��O��?u�0��(�)wB����c���I��+�1O'.5��O���:�}J�ɶZ_�h�T$�gYMIf�~���5�@�xL�U<Ϳ�iF�Y�X�7R?9 �Z7/c5�?X�}n���u���y�<y��́����������A'�O���'I�Y�e���ˣ?��)H��gϏN��9@Q}���R���	�<�q
KG��:u��9�ש��q9p��g<���h�.p1`/yp�~��#�6Y�Y�zN��#/�V��J}l����� 9�yXG��.'mEj#��0�R����/�<!б��Z�<�}��[�����r8��}�v� C�@Sp�D�_�b��;��T��e/���h8Dx����0��A���P/N���pB�{}'�G}I�����C;�����W�{�oQ������^�����ԟzÍ��[O��uB0#Ԕ:kB�Ŏ�	i����QK��ys���+4�:�
���ќ�}�e��חj,�=�*"�6v�A5��4(�B�)h甍���Ds�`q���is����<#����{�B�w�p&��?����9�$=��@-��7� ~�+��R;!�NI�P�%�ۃ��4]����2XS�J"=�$��XNB	@��08@�
�~��0�q���;$�x.x$�G��b�m^����F؍��A!
���&���q�$= [���Pځ�19��&[��Ck�W@U֟��H�ӣ�]��(��R+p�C�2S�;�E���aę��pp �Eh�����4�I��WP�p�;b`�^�c���܏[������"�!���(g 8�N���������9TE�h5�R:f��N��w�	+��;�ʂ*�pĠ�f�1�$��W��t�-�x�?!������)W��	Ζ�#	|%9���8#B1��k��耼�����?�a?�'s����	��� ���w�֝`ӌ�}�iE?�R��Ň�����A�8.A[܁AЏ�*�6��j�׹s�M�/���hg�0���a4V�i�mc ˁ᥾nt^�������� !�)��Ы��!; �48�D��D�;�"o�br��4���H��rb+��p4NH��M�r�Zw~O&k��3@n>F0�ؗ���{������pp\��n6��|��]�(��U$��Z��v�ɗh����Y�]�����ה�t�֛8ӄ#Y^���a��!M�=�2j݉��Xj#��o�?3�	@���a��<N�\b-��#�	a��?�}���U-[�����h~��_�0y��!�2]HPv����>r�K�@4 U9��݉��R]����@ٿ~����ݛQ>tiQ?��,��3쑰�@���(�A��L�˟��9����,�I���9G
��X6�j��>g���1,g9�b�ČS�mm��=��fp��n,��Ԭ�v�>���n=�b�����&%�}"X�ݫ���H{�m2�&Jc��}�v�G�Yn/Y��]'�Ec��0+���w���Q�p,��Qғo@��<��fV�y���g�܉UM;�c�M���{	r;����-��ξu�9��o�@�L�LAYJv��2�fUk�|��ې ��a�
m�7`
��Y�o� �yX{���N}�Q�Qx\
?b�e���M���t�/J�`���������ӕ�c�b
|��8��m������	�d���s�W!���6�)#+.�(�`9��\~�ˡ.�e��~;�<�/cX���M�t��'�!��B��($�k���{�v�ø� ��c�����)��Q��������ɫקOtn�S?���4@o;z%�50��g��o��> �����Xs"6���"Kr���b��#�k���n���/j��'`��It&��cM�aq�e[���,���S��h��w\2xWޥ��<�i2薣(
��}��u��x:@ƍ���~�|�?1���gd����sS������m򋦞�́Л3Z3�������`������4�Ǡ��S��l-',�v-7�ut؝,�`��$"�Dr\�s���;���0f�$�E1Ui���)����i�����i���7��3��Z�����,u>Q6��;.���7fo�������N����ݭ���<5y�g~Q�((O\j�i�C��%)ҤI�a{�Q�f�I}ܲ"+Ѫ`��#��Z��U-2Dq
)C᥶�l�W^�*�ۍY��^#���۾rG�w��>��F�b�Y�� ݜ,6��y��`-l-�ʐ7�7a�B�R���rp�@��UwP��Z��_.�U��U�oH������@�^)��
�W6��eH8-j~f�"����+����Y�T�B��b�S��%�3K��j��k�^���
}� g��{�Cq�)��˵���G/�m�9�]7^le�d0c�R4(�J�+�nM?����(�A��lp�LE����*�����`l䕵^�*���Ýr].-��X��0jm& 6�<=�M6��y}Te�6��q�+�9�7�4.���7�2���j"maCkD����4������#⣹�	VB�`�v���~G�i��֎e�	2��̽��f��V�t�KNo֢ՠ���g�I��o����w65�r�4�����v
(j�P��C^�$�ǉ�^OX-&\W�L	�F���"C,h/�YNM�.���*=��H@��LW�I�Q`�O{�@NV�S��|�\Ӑ���nNb��^�����A�`I"��d��Z��:NŔ6�c$N��zEY��ư����?�2.�,q ��V8_�g��К�s=	���a5F��i_��X
	 vR���fo+m$�Q�YP�'��~0����d�&�� os혓�� ���G'oq�,��fFX�6�om=�eq�l�Z�"��!�.H�ndc�Nt3����#��$#��!��U��%�ֵp�% ��
�+��خq1�,փ�y��p7��1���I��?��r��Z2(0��fl�UuHt�f�<�v�����@"���52Z����Q�a)>�Z�M��m��BN���s]t���xͱ*���<��}7�k�H)e��a/���a:h���Z�!)Adg�W��P�`�<��1��l�<�:u�y�1G���=��R(��`�^
v>o5 =�od����1J2�&�O�����(]`�U�U�d�iB;�����Z�6Y}��Y4Ҧ���j�*�+���������]�H����l[�X��vq����瀀�\R��:��	q��V���+a��ѱG�*�ZF����S�����.rS�g�	�g�b��������F���Y?�g�����~���Y?�g�����~���Y?�����M&�� �  