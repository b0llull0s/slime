; =============================================================================
; COMMAND EXECUTION ENGINE - Standalone Command Processing Block
; =============================================================================
; Copy this entire file into any ASM project for instant command execution
; 
; Features:
;   - Execute shell commands with output capture
;   - Execute commands directly (stdout only)
;   - Execute command arrays/lists
;   - Proper process management (fork/exec/wait)
;   - Output redirection capabilities
;   - Error handling and cleanup
;
; Usage:
;   1. Include this block in your .asm file
;   2. Add to .data section: shell db '/bin/sh', 0 and arg_c db '-c', 0
;   3. Add command arrays as needed
;   4. Call: mov rdi, command_string ; call execute_command
;   5. Or: mov rdi, command_array ; call execute_command_list
; =============================================================================

section .data
    ; Shell configuration
    shell db '/bin/sh', 0
    arg_c db '-c', 0
    
    ; Status messages (optional, for debugging)
    msg_executing db '[+] Executing: ', 0
    msg_completed db '[+] Command completed', 10, 0
    msg_failed db '[-] Command failed', 10, 0

section .bss
    ; Command execution workspace
    exec_buffer resb 4096
    child_pid resq 1
    exit_status resq 1

section .text

; =============================================================================
; MAIN COMMAND EXECUTION INTERFACE
; =============================================================================

; Execute a single command
; Input: rdi = pointer to command string
; Returns: rax = exit status (0 = success, non-zero = error)
execute_command:
    push rbp
    mov rbp, rsp
    push rdi                         ; Save command string
    
    ; Fork process
    mov rax, 57                      ; syscall: fork
    syscall
    
    test rax, rax                    ; Check return value
    jz .child_process                ; If zero, we're in child process
    jmp .parent_process              ; Otherwise, we're in parent process

.child_process:
    ; Set up arguments for execve
    push 0                           ; NULL terminator
    push qword [rsp + 8]             ; Command string
    push arg_c                       ; "-c" argument
    push shell                       ; Shell path
    mov rsi, rsp                     ; Argument array
    
    ; Execute command
    mov rax, 59                      ; syscall: execve
    mov rdi, shell                   ; Program to execute
    xor rdx, rdx                     ; No environment variables
    syscall
    
    ; Exit if execve fails
    mov rax, 60                      ; syscall: exit
    mov rdi, 1                       ; exit code 1
    syscall

.parent_process:
    ; Store child PID
    mov [child_pid], rax
    
    ; Wait for child to complete
    mov rdi, rax                     ; Child PID
    mov rax, 61                      ; syscall: wait4
    sub rsp, 8                       ; Reserve space for status
    mov rsi, rsp                     ; Status pointer  
    xor rdx, rdx                     ; Options = 0
    xor r10, r10                     ; rusage = NULL
    syscall
    
    ; Get exit status
    mov rax, [rsp]                   ; Load status
    add rsp, 8                       ; Clean up status space
    mov [exit_status], rax           ; Store for later use
    
    add rsp, 8                       ; Clean up command string from stack
    mov rsp, rbp
    pop rbp
    ret

; Execute a list of commands (array terminated by NULL)
; Input: rdi = pointer to command array (array of string pointers)
; Returns: rax = number of failed commands
execute_command_list:
    push rbp
    mov rbp, rsp
    push rbx                         ; Save command array pointer
    push r12                         ; Save failure counter
    
    mov rbx, rdi                     ; Command array pointer
    xor r12, r12                     ; Failure counter = 0
    
.loop:
    mov rdi, [rbx]                   ; Get next command pointer
    test rdi, rdi                    ; Check if NULL (end of list)
    jz .done                         ; If NULL, exit loop
    
    ; Execute command
    call execute_command
    test rax, rax                    ; Check exit status
    jz .next                         ; If success, continue
    inc r12                          ; Increment failure counter
    
.next:
    add rbx, 8                       ; Move to next command pointer
    jmp .loop                        ; Continue loop
    
.done:
    mov rax, r12                     ; Return failure count
    
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

; Execute command with output capture to buffer
; Input: rdi = command string, rsi = output buffer, rdx = buffer size
; Returns: rax = bytes captured, -1 on error
execute_command_capture:
    push rbp
    mov rbp, rsp
    push rdi                         ; Command string
    push rsi                         ; Output buffer
    push rdx                         ; Buffer size
    
    ; Create pipe for output capture
    sub rsp, 16                      ; Space for pipe fds
    mov rax, 22                      ; pipe syscall
    mov rdi, rsp                     ; Pipe array pointer
    syscall
    test rax, rax
    js .error
    
    ; Fork process
    mov rax, 57                      ; fork syscall
    syscall
    test rax, rax
    jz .child_capture
    jmp .parent_capture

.child_capture:
    ; Close read end of pipe
    mov rax, 3                       ; close syscall
    mov rdi, [rsp]                   ; Read fd
    syscall
    
    ; Redirect stdout to write end of pipe
    mov rax, 33                      ; dup2 syscall
    mov rdi, [rsp + 8]               ; Write fd
    mov rsi, 1                       ; stdout
    syscall
    
    ; Close write end (we've duplicated it)
    mov rax, 3                       ; close syscall
    mov rdi, [rsp + 8]               ; Write fd
    syscall
    
    ; Execute command
    push 0                           ; NULL terminator
    push qword [rsp + 32]            ; Command string
    push arg_c                       ; "-c" argument
    push shell                       ; Shell path
    mov rsi, rsp                     ; Argument array
    
    mov rax, 59                      ; execve syscall
    mov rdi, shell
    xor rdx, rdx
    syscall
    
    ; Exit if execve fails
    mov rax, 60
    mov rdi, 1
    syscall

.parent_capture:
    ; Close write end of pipe
    push rax                         ; Save child PID
    mov rax, 3                       ; close syscall
    mov rdi, [rsp + 8]               ; Write fd (accounting for pushed PID)
    syscall
    
    ; Read from pipe into buffer
    mov rax, 0                       ; read syscall
    mov rdi, [rsp]                   ; Read fd (accounting for pushed PID)
    mov rsi, [rsp + 32]              ; Output buffer
    mov rdx, [rsp + 24]              ; Buffer size
    syscall
    push rax                         ; Save bytes read
    
    ; Close read end of pipe
    mov rax, 3                       ; close syscall
    mov rdi, [rsp + 8]               ; Read fd (accounting for pushed values)
    syscall
    
    ; Wait for child
    pop rdx                          ; Restore bytes read
    pop rdi                          ; Child PID
    push rdx                         ; Save bytes read again
    
    mov rax, 61                      ; wait4 syscall
    sub rsp, 8
    mov rsi, rsp
    xor rdx, rdx
    xor r10, r10
    syscall
    add rsp, 8
    
    pop rax                          ; Return bytes read
    jmp .cleanup

.error:
    mov rax, -1

.cleanup:
    add rsp, 40                      ; Clean up stack (pipe fds + saved values)
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; UTILITY FUNCTIONS
; =============================================================================

; Get last command exit status
; Returns: rax = exit status of last executed command
get_last_exit_status:
    mov rax, [exit_status]
    ret

; Kill running command (if any)
; Returns: rax = 0 on success, -1 on error
kill_running_command:
    cmp qword [child_pid], 0
    je .no_process
    
    mov rax, 62                      ; kill syscall
    mov rdi, [child_pid]             ; PID to kill
    mov rsi, 9                       ; SIGKILL
    syscall
    
    ; Clear stored PID
    mov qword [child_pid], 0
    ret

.no_process:
    xor rax, rax                     ; Success (nothing to kill)
    ret

; =============================================================================
; CONVENIENCE FUNCTIONS
; =============================================================================

; Execute command and ignore output (silent execution)
; Input: rdi = command string
; Returns: rax = exit status
execute_silent:
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Redirect stdout and stderr to /dev/null
    ; Fork first
    mov rax, 57                      ; fork
    syscall
    test rax, rax
    jz .child_silent
    
    ; Parent: wait for child
    mov rdi, rax
    mov rax, 61                      ; wait4
    sub rsp, 8
    mov rsi, rsp
    xor rdx, rdx
    xor r10, r10
    syscall
    mov rax, [rsp]
    add rsp, 8
    jmp .done_silent

.child_silent:
    ; Open /dev/null
    mov rax, 2                       ; open syscall
    mov rdi, devnull
    mov rsi, 1                       ; O_WRONLY
    syscall
    
    ; Redirect stdout and stderr
    mov rdi, rax                     ; /dev/null fd
    mov rsi, 1                       ; stdout
    mov rax, 33                      ; dup2
    syscall
    
    mov rdi, [rsp - 8]               ; /dev/null fd (still in rdi from above)
    mov rsi, 2                       ; stderr
    mov rax, 33                      ; dup2
    syscall
    
    ; Execute command normally
    mov rdi, [rsp]                   ; Command string
    call execute_command
    
    ; Exit child
    mov rax, 60
    xor rdi, rdi
    syscall

.done_silent:
    add rsp, 8
    mov rsp, rbp
    pop rbp
    ret

; Data for silent execution
section .data
devnull db '/dev/null', 0

; =============================================================================
; USAGE EXAMPLES AND INTEGRATION PATTERNS:
; =============================================================================
; 
; ; Basic usage - execute single command:
; section .data
;     my_command db 'ls -la', 0
; 
; section .text
; _start:
;     mov rdi, my_command
;     call execute_command
;     ; rax contains exit status
; 
; ; Execute command list:
; section .data
;     cmd_list dq cmd1, cmd2, cmd3, 0  ; NULL terminated array
;     cmd1 db 'whoami', 0
;     cmd2 db 'id', 0  
;     cmd3 db 'pwd', 0
; 
; section .text
; _start:
;     mov rdi, cmd_list
;     call execute_command_list
;     ; rax contains number of failed commands
; 
; ; Capture command output:
; section .bss
;     output_buf resb 1024
; 
; section .text
; _start:
;     mov rdi, my_command
;     mov rsi, output_buf
;     mov rdx, 1024
;     call execute_command_capture
;     ; rax contains bytes captured
;     ; output_buf contains command output
; =============================================================================
