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
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(zip|tar\.(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(zip|tar\.(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
cd "/tmp/$BASE-test"

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

# Unpack the submission (or copy the dir)
if [ -z "$EXT" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".zip" ]; then
  unzip    "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
NDIRS=$(find . -mindepth 1 -maxdepth 1 -type d | wc -l)
test "$NDIRS" -gt 1 && \
  echo "Malformed archive! Expected exactly one directory" && exit 1
test  "$NDIRS" -eq 0  -a  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 0  && \
  echo "Empty archive!"
if [ "$NDIRS" -eq 1 ]; then
  cd "$(find . -mindepth 1 -maxdepth 1 -type d)"
fi

# Deploy additional binaries so that validate.sh can use them
mkdir ../grade-driver-tools
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade ../grade-driver-tools/realpath
export PATH="$PATH:$(realpath grade-driver-tools)"

# Unpack the testbench and grade
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1
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
� ]�q[ �Z[s�F�����Ē��\|�1�KlCH��bH��W[�F�D-��/TRP����u��~�[�h�c`wI���S�o�>�����9�_�ݠ�X[��͍�F�wW�+++��Fce�u��l���]ak�KHd�#Ʈ�x����}l���\����z}��i���WW/��Z��W������\�?��w��߹w�e�g��u�U����ۓ�K�&��	=��"
�"�|>܏	�$�я�7%�抁\�r��g6��i$jR`Q '1����U�nHXh��~�� *0A<���9���"��M�
����%��<N"!	����Q��_�_�����{&p]�솑��?�
�	Zg��C�����%�H�i�?���r��e.da�Y��:�c�ܭI��@`"� �Hֹ;�#�OⰖJ.p�^�@D<� n��=�ʩ<b�a���]�� ������e���U��@�g��d�j�",Q�Lġq|������֢���l�v��"H%���I�S��JȠ}������sRZ*z�9׋��J�3�r�L޹w��N�	��}2H���W�����29�1�f;UM�V��"�Eb��~�a��I	��< -fĢ��>iׇn.MF(��sx\Y�#1"�g��b�2�_��Md�T"�CV3���A�"
���މL�o�� �H�}S�Ƣ)����!V�Ej߽��҂d��փ�߷R�l�N���/
��0�br W�}[y��ҿ�[��d���z�̵�����~	LVINc/2 �6i�L��6�?�?�`�L:�B��_�h����Ց̻�����m�ym��"���p��[S��
���G�80��X(��W]�K`c��ɒ5����0��w���-i������O�R��PN�l#7O�Ų�k\]4wv,V���P�NDQ����r�M�^GeK[A�]��;��q��Z����o�}�%�?qΰ���M�s���4�-��^0��K��^���)J�>Ylzbф3ZJ
Q53���LBd%�_�P	�"cj��?�(7��RD�����Kk�y��E���=���Cw���C�"�Uk�[8���^/�p-Ζ!.�Y��)!f�x�.ǿ�P�S�2�۵����Cs�Sz�BrU�� �Ld#�ٽs���@B2B*���퓡��ΓtC�$M�#8�>^�H�U���Qh�������_�9��Z\4O��&�`0x�Zk�u��W�ٶ��|�XD;҃)��L�����Y/LU���?�IIC��62:���1t��}��T/	$c0%�@*9Mk��?~C����lT�ukH,s`���Dl3S="i����Vţ�;��f��E��?��I�G:�e�U���i��<�۹���=	������u�;�r���	�[ȩM&|3��g9���ٗ�|높�$.&	K,C�g8W��	:O�n�`q�LM��]���a��y�s9
iy��i|��o66��oe���ܠ�o��R�|�PGd��=�g�w0���T͆���UN=Qh�,dv�M��E�Z�S+]!�S�<7�n8��Ʊ���3�b����N
V�sl�׆�u�3U����.f�:*�M���`3+t��:f�-L��v	k�HqPv�F��PX��ZlK}��	G��K��YY�f;G�H�����FVX��f�{��}�\U	QZZ@q�Q n`�q"�BXEl�f�����?Eva�UP�$�P���>%�X`;gB�q`%��i��ҢZ��ju��
B�r�vӐ}!�%�,�H��?@��7�Y}���P����OS��
�Y�Q��#\`�( �h���������y��{�N0C4����nx�p�d���!�DU����RG.��	:r4=�#�m̠��c.Q�?`/VC���/G�	P�5?����ꁔHd`*]/�ܰ��,��J|�$y=/Z�P�.ܤ�p�&(4�->�ؒ�cK��[���;�'X�Y��~H+�#���^�XK�f�s��c��P���~��=	=�^�x���d�Q|}��t�F�Ｘnn�Z�f���	�(���z��;�
���%�+��_Q���
qI_����>�����,�_���bd��ղ��u��>c8<.X&}Ք��w�\�-�s������g
Ə@��_�f�9.U���L�(Q���P��� ��3�DӸ��t$
���<�Aƥ]@u_!���'mB����1H��CÇ�s>�y�����K1妽����y��D �H�҇��F�?�$��ak������d�%`�_�^�:"jJ8�/�J���֥�C%�R�r4�V�����H��*�RQ�J�*�HY����OmnX�/��zM\� �Oq E/�6Lhw��Ț.�"��N��2wK��S|�'�W�N�.S]�^�gS�JCzV���X���ɴSG�'�]�#H$�x1m�@p����]f$�Xp����į*1\!��P�n{�%��30��ɘ��0��wN�IS���S��=��#W�7��f���ky!�J��F���-�KTYl}�ݼi���4��{�s=���u0~�a[l}�]eB
11ٺi��6n�\��ą0�Ʒ(� �`w�����-Dh�"���M؞���#
��o�G[#O�����I�v��u�c��ek۪wV��K��n�O[�ȝp�d���;�f<��Rxdm����k����~`���'�]Wdq$;]����l�I"ln dM�X���=ت�y����O=IW����u�lY6]Z��ح%v����?�D�զ���Iq��V�;"c_ٰ[Uև�uϝ�T�.�p��'t$�V�c�76�G7n�nZS�O�`QY>�r)�մ�<��xw��/�
�]d��Ƥn^�;U�����K)�Ԑ�S ���ܭ'�H'''��>6]X1.l�㧓﫟�F󧧨�+F>M���)|t�P�tN&�Ӭ�f �G��·Qk��i}b�����mӧ�5/��8V�D%��	A?�0h8¬��Y���,��X��*ݑ��T4�lܙ\%e}z4{_�I���So��O]�C}q���Gqg��^J��7o�dv��3e =3=�A=�N�8���W������h�d:?\D}��.�>6]\1�"M������߾�̩{>ǳ�|��4�������\/����:"껩�s�T�El��'O-�J4�b���Uk��B��J��R��Z��f�G�c���E�5�V=����arJ���]��<�^t��vsV����/��e��רN��-ְaN�j��-ִ���L��(�D�kV�T��.B�"��I�\�^�VYx��P��մ2�S�^O�qk�8� ;�Ob&d�T�Q���ĝb�����eօк�@fe����ʋJz��� �kvS�%��u�Jav1T�z��H��]��W}�[��m4�m��4^���SB	%�PB	%�PB	%�PB	%�PB	%�PB	%�PB	%�PB	%�PB	%�PB	��@�\ P  