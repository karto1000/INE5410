//Habilita a função fdopen(). 200809L corresponde ao POSIX de 2008, mas um valor de 1 (POSIX.1, 1990) já seria suficiente.
#define _POSIX_C_SOURCE 200809L 
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define N_CHILDREN 2

int child_main(int downstream, int upstream);

int main(int argc, char** argv) {
    //Pipes
    int downstream[2];
    int   upstream[2]; 
    //  (pai)>---->---->---->---->--+
    //           (fechado)          v
    //               |              v
    //          downstream[0]  downstream[1]
    //              | |            |v|        (memória do pai)
    // ~~~~~~~~~~~~~|v|~~~~~~~~~~~~|v|~~~~~~~~~~~~~~~~
    //              |v|            | |        (memória do filho)
    //          downstream[0]  downstream[1]
    //               v              |
    //               v          (fechado)
    //               +---->---->---->---->---->(filho)
    //
    // downstream[0] e downstream[1] são ints que guardam 
    // file descriptors (fd's, para os íntimos). Pai e filho 
    // usam principalmente essas funções para ler e escrever:
    //   int  read(int fd, void* buf, size_t bytes)
    //   int write(int fd, void* buf, size_t bytes)
    //
    // Tudo que (pai) escreve em downstream[1], o filho 
    // consegue ler em downstream[0]. 
    // O pipe upstream funciona ao contrário: tudo que o filho 
    // escreve em upstream[1] pode ser lido pelo pai em upstream[0].
    // CUIDADO: um único processo não pode ler *E* escrever no mesmo 
    // pipe, por isso ou pipe[0] ou pipe[1] precisam estar fechados!


    //Pai deve criar os pipes
    //Cria um pipe onde o pai escreve e o filho lê
    if (pipe(downstream)) {
        printf("Error creating downstream pipe\n");
        return 1;
    }
    //Cria um pipe onde o filho escreve e o pai lê
    if (pipe(upstream)) {
        printf("Error creating upstream pipe\n");
        return 1;
    }

    //Cria filho e configura pipes
    pid_t child;
    if ((child = fork())) {
        // (pai executa aqui)
        close(downstream[0]); //pai só escreve
        close(  upstream[1]); //pai só lê
    } else {
        // (filho executa aqui)
        close(downstream[1]); //filho só lê
        close(  upstream[0]); //filho só escreve
        return child_main(downstream[0], upstream[1]);
    }
    
    //Envia uma mensagem pro filho
    const char* str = "grandes garfos garfearam o garfeiro";
    //               +----> write_end do pipe
    //               |   +-----> string a ser escrita
    //               |   |    +---> tamanho da string (sem o '\0')
    //               v   v    v
    write(downstream[1], str, strlen(str));

    //Fecha o write end do pipe, para que o filho saiba que 
    //não mandaremos mais nada
    close(downstream[1]);

    //Lê a resposta do filho
    char buf[256] = {0}; //inicia com tudo zerado
    int bytes = read(upstream[0], buf, 255);
    //strings em C terminam com um \0, read() e write() não 
    //tratam desse detalhe importante pro printf funcionar!
    buf[bytes] = '\0'; 
    printf("Filho disse: %s\n", buf);
    
    //fecha nosso lado do upstream
    close(upstream[0]);

    return 0; //tchau
}

int child_main(int downstream, int upstream) {
    // scanf() só funcionado com FILE*. (fscanf)
    // cria um FILE* para acesso ao pipe downstream
    FILE* downstream_file = fdopen(downstream, "r");

    char word[4096];
    while (fscanf(downstream_file, "%4096s", word) > 0) ;

    //Envia a última palavra pro pai
    write(upstream, word, strlen(word));
    fclose(downstream_file); // tambem fecha downstream
    close(upstream);         // fecha nosso lado do pipe
    return 0;
}
