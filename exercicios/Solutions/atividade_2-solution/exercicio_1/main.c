#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/wait.h>

//       (pai)      
//         |        
//    +----+----+
//    |         |   
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!


int main(int argc, char** argv) {
    pid_t pid;
    for (int i = 0; i < 2; ++i) {
        if ((pid = fork())) {
            printf("Processo pai criou %d\n", pid);
        } else {
            printf("Processo filho %d criado\n", getpid());
            return 0;
        }
    }
    while (wait(0) >= 0) ;

    printf("Processo pai finalizado!\n");       
    return 0;
}
