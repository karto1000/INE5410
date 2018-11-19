#include <time.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <sys/resource.h>
#include "bandeja.h"

bandeja_t* campo_de_visao_da_tia;

bandeja_t* pegar_bandeja() {
    return (bandeja_t*)calloc(1, sizeof(bandeja_t));
}

void aproximar_bandeja(bandeja_t* b) {

    campo_de_visao_da_tia = b;


}

int bandeja_vazia(bandeja_t* b) {
    return b->carne == 0;
}

void colocar_carne() {

    campo_de_visao_da_tia->carne = 23;

}

void comer(bandeja_t* b) {
    int ms = 10*rand()/(double)RAND_MAX;
    struct timespec ts = {0, ms*1000000};
    nanosleep(&ts, NULL);
    free(b);
}

void fazer_bandejaco() {
    for (int amigo = 0; amigo < 100; ++amigo) {
        for (int batida = 0; batida < 200; ++batida) {
            printf("PLACT! "); fflush(stdout);
        }
    }
}

int get_num_alunos(int argc, char** argv) {
    int alunos = -1;
    if (argc > 2) {
        alunos = atoi(argv[1]);
    }
#ifdef RLIMIT_NPROC
    struct rlimit rl;
    if (getrlimit(RLIMIT_NPROC, &rl)) {
        if (alunos == -1) {
            perror("Erro ao ler RLIMIT_NPROC assumindo 57. Motivo:");
            return 57;
        } else {
            fprintf(stderr, "Erro ao ler RLIMIT_NPROC assumindo que será "
                    "possível cirar %d threads. Motivo: %s\n",
                    alunos, strerror(errno));
            return alunos;
        }
    }
    if (alunos == -1) {
        alunos = rl.rlim_max/2;
        alunos = alunos > 1000 ? 1000 : alunos;
    }
    if (rl.rlim_cur != rl.rlim_max) {
        unsigned long old = rl.rlim_cur;
        rl.rlim_cur = rl.rlim_max;
        if (setrlimit(RLIMIT_NPROC, &rl)) {
            fprintf(stderr, "Erro ao subir RLIMIT_NPROC de %lu para %lu. "
                    "Motivo: %s\n", old, rl.rlim_max, strerror(errno));
            rl.rlim_cur = old;
        }
    }
    if (alunos > rl.rlim_cur) {
        fprintf(stderr, "Número solicitado de alunos (%d) está acima do "
                "suportado nesse computador (%lu)!\n", alunos, rl.rlim_cur);
        return -alunos;
    }
#else
    if (alunos == -1)
        alunos = 48;
#endif /*RLIMIT_NPROC*/
    return alunos;
}
