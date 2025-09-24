section .data
    ; Shell command
    shell db '/bin/sh', 0
    arg_c db '-c', 0
    
    ; Crypto engine - function pointer for decryption
    decrypt_func dq simple_xor_decrypt
    
    ; Command array (pointers to commands)
    commands dq cmd_env, cmd_sudo, cmd_hostname, cmd_ifconfig, cmd_mount, cmd_uname, cmd_getcap, cmd_find, cmd_grep, cmd_cat_group, cmd_cat_crontab, cmd_netstat, 0

section .bss
    ; Buffer for decoded commands
    cmd_buffer resb 256

section .text
    global _start

_start:
    mov rsi, commands        ; Load command array address
    
.loop:
    mov rdi, [rsi]           ; Get next command pointer
    test rdi, rdi            ; Check if NULL (end of list)
    jz .exit                 ; If NULL, exit
    
    push rsi                 ; Save command array pointer
    call copy_and_decode     ; Copy command to buffer and decode (returns decoded cmd in rdi)
    call execute_command     ; Execute the command (rdi has decoded command)
    pop rsi                  ; Restore command array pointer
    
    add rsi, 8               ; Move to next command pointer
    jmp .loop                ; Continue loop
    
.exit:
    ; Exit program
    mov rax, 60              ; syscall: exit
    xor rdi, rdi             ; exit code 0
    syscall

; Copy command to buffer and decode it using function pointer
; Input: rdi = pointer to encoded command
; Output: rdi = pointer to decoded command in buffer
copy_and_decode:
    call [decrypt_func]      ; Call current decryption function
    ret

; =============================================================================
; CRYPTO ENGINE - Modular decryption functions
; =============================================================================

; Simple XOR decryption (original method)
; Input: rdi = pointer to encoded command
; Output: rdi = pointer to decoded command in buffer
simple_xor_decrypt:
    push rsi                 ; Save registers
    
    mov rsi, rdi             ; Source
    mov rdi, cmd_buffer      ; Destination
    
.decode_loop:
    mov al, [rsi]            ; Get encoded byte
    test al, al              ; Check for null terminator
    jz .decode_done          ; If null, we're done
    xor al, 0xAA             ; Decode byte (XOR with 0xAA)
    mov [rdi], al            ; Store decoded byte
    inc rsi                  ; Move to next source byte
    inc rdi                  ; Move to next destination byte
    jmp .decode_loop         ; Continue loop
    
.decode_done:
    mov byte [rdi], 0        ; Add null terminator to decoded string
    mov rdi, cmd_buffer      ; Return pointer to decoded command
    
    pop rsi                  ; Restore registers
    ret

; Multi-byte XOR decryption (more secure)
; Input: rdi = pointer to encoded command
; Output: rdi = pointer to decoded command in buffer
multibyte_xor_decrypt:
    push rsi                 ; Save registers
    push rdx                 ; Save key index
    
    mov rsi, rdi             ; Source
    mov rdi, cmd_buffer      ; Destination
    xor rdx, rdx             ; Key index = 0
    
.decode_loop:
    mov al, [rsi]            ; Get encoded byte
    test al, al              ; Check for null terminator
    jz .decode_done          ; If null, we're done
    
    ; Get current key byte
    mov cl, [xor_key + rdx]  ; Get key byte
    xor al, cl               ; Decode with current key byte
    mov [rdi], al            ; Store decoded byte
    
    inc rsi                  ; Move to next source byte
    inc rdi                  ; Move to next destination byte
    inc rdx                  ; Next key byte
    cmp rdx, 4               ; Check if we've used all 4 key bytes
    jl .decode_loop          ; If not, continue
    xor rdx, rdx             ; Reset key index to 0
    jmp .decode_loop         ; Continue loop
    
.decode_done:
    mov byte [rdi], 0        ; Add null terminator to decoded string
    mov rdi, cmd_buffer      ; Return pointer to decoded command
    
    pop rdx                  ; Restore registers
    pop rsi
    ret

; ROT13-style rotation cipher
; Input: rdi = pointer to encoded command
; Output: rdi = pointer to decoded command in buffer
rot_decrypt:
    push rsi                 ; Save registers
    
    mov rsi, rdi             ; Source
    mov rdi, cmd_buffer      ; Destination
    
.decode_loop:
    mov al, [rsi]            ; Get encoded byte
    test al, al              ; Check for null terminator
    jz .decode_done          ; If null, we're done
    sub al, 13               ; ROT13 decryption (subtract 13)
    mov [rdi], al            ; Store decoded byte
    inc rsi                  ; Move to next source byte
    inc rdi                  ; Move to next destination byte
    jmp .decode_loop         ; Continue loop
    
.decode_done:
    mov byte [rdi], 0        ; Add null terminator to decoded string
    mov rdi, cmd_buffer      ; Return pointer to decoded command
    
    pop rsi                  ; Restore registers
    ret

; Crypto engine data (add to existing .data section)
xor_key db 0xAA, 0xBB, 0xCC, 0xDD  ; 4-byte XOR key for multibyte encryption

; =============================================================================
; CRYPTO ENGINE UTILITIES
; =============================================================================

; Switch crypto method
; Input: rdi = crypto method (0=simple_xor, 1=multibyte_xor, 2=rot)
set_crypto_method:
    cmp rdi, 0
    je .set_simple_xor
    cmp rdi, 1
    je .set_multibyte_xor
    cmp rdi, 2
    je .set_rot
    ret                      ; Invalid method, no change
    
.set_simple_xor:
    mov qword [decrypt_func], simple_xor_decrypt
    ret
    
.set_multibyte_xor:
    mov qword [decrypt_func], multibyte_xor_decrypt
    ret
    
.set_rot:
    mov qword [decrypt_func], rot_decrypt
    ret

; Execute a command
; Input: rdi = pointer to command string
execute_command:
    ; Fork process
    mov rax, 57              ; syscall: fork
    syscall
    
    test rax, rax            ; Check return value
    jz child_process         ; If zero, we're in child process
    jmp parent_process        ; Otherwise, we're in parent process

child_process:
    ; Set up arguments for execve
    push 0                   ; NULL terminator
    push rdi                 ; Command string
    push arg_c               ; "-c" argument
    push shell               ; Shell path
    mov rsi, rsp             ; Argument array
    
    ; Execute command
    mov rax, 59              ; syscall: execve
    mov rdi, shell           ; Program to execute
    xor rdx, rdx             ; No environment variables
    syscall
    
    ; Exit if execve fails
    mov rax, 60              ; syscall: exit
    mov rdi, 1               ; exit code 1
    syscall

parent_process:
    ; Try a minimal wait4 implementation
    mov rdi, rax             ; Child PID
    mov rax, 61              ; syscall: wait4
    sub rsp, 8               ; Reserve space for status
    mov rsi, rsp             ; Status pointer  
    xor rdx, rdx             ; Options = 0
    xor r10, r10             ; rusage = NULL
    syscall
    add rsp, 8               ; Clean up status space
    
    ret

; Encoded commands (XOR with 0xAA for obfuscation)
; Now in .text section to make them executable
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