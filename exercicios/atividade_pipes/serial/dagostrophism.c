#define _POSIX_C_SOURCE 200809L //required for nanosleep
#include <time.h>
#include <stdio.h>
#include <string.h>
#include "dagostrophism.h"

// *============================* 
// |   NÃO ALTERE ESSE ARQUIVO  |
// *============================*
// |                            |
// |            /\              |
// |           /  \             |
// |          /    \            |
// |         /      \           |
// |        /        \          |
// |       / RISCO DE \         |
// |      /   CHOQUE   \        |
// |     /   ELÉTRICO   \       |
// |    *----------------*      |
// *============================*

int is_dagostrophic(const char* word) {
    if (!word) {
        printf("WARNING [is_dagostrophic]: word é nulo! retornarei 0\n");
        return 0;
    }
    struct timespec interval = {0, 66600000};
    nanosleep(&interval, NULL);
    size_t len = strlen(word);
    size_t last = len - 1, mid = len/2 + 1;
    for (int i = 0; i < mid; ++i) {
        if (word[i] != word[last-i]) return 0;
    }
    return 1;
}
