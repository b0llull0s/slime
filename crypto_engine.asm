; =============================================================================
; CRYPTO ENGINE - Standalone Modular Encryption/Decryption Block
; =============================================================================
; Copy this entire file into any ASM project for instant crypto capabilities
; 
; Usage:
;   1. Include this block in your .asm file
;   2. Add to .data section: decrypt_func dq simple_xor_decrypt
;   3. Add to .bss section: cmd_buffer resb 256
;   4. Call: mov rdi, encoded_string ; call [decrypt_func]
;   5. Switch methods: mov rdi, METHOD_NUM ; call set_crypto_method
; =============================================================================

section .data
    ; Crypto engine - function pointer for decryption
    decrypt_func dq simple_xor_decrypt
    
    ; Multi-byte XOR key (change this for different security)
    xor_key db 0xAA, 0xBB, 0xCC, 0xDD

section .bss
    ; Buffer for decoded commands
    cmd_buffer resb 256

section .text

; =============================================================================
; MAIN CRYPTO INTERFACE
; =============================================================================

; Copy command to buffer and decode it using function pointer
; Input: rdi = pointer to encoded command
; Output: rdi = pointer to decoded command in buffer
copy_and_decode:
    call [decrypt_func]      ; Call current decryption function
    ret

; =============================================================================
; CRYPTO METHODS - Add more here as needed
; =============================================================================

; Simple XOR decryption (fast, basic obfuscation)
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

; Multi-byte XOR decryption (better security, rotating key)
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

; ROT13-style rotation cipher (simple but effective against basic detection)
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

; Add more crypto methods here following the same pattern:
; your_custom_decrypt:
;     ; Your implementation
;     ; Input: rdi = encoded string
;     ; Output: rdi = cmd_buffer with decoded string
;     ret

; =============================================================================
; CRYPTO ENGINE UTILITIES
; =============================================================================

; Switch crypto method at runtime
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

; Get current crypto method (useful for debugging)
; Output: rax = method number
get_crypto_method:
    mov rax, [decrypt_func]
    cmp rax, simple_xor_decrypt
    je .return_simple
    cmp rax, multibyte_xor_decrypt
    je .return_multibyte
    cmp rax, rot_decrypt
    je .return_rot
    mov rax, -1              ; Unknown method
    ret
    
.return_simple:
    mov rax, 0
    ret
    
.return_multibyte:
    mov rax, 1
    ret
    
.return_rot:
    mov rax, 2
    ret

; =============================================================================
; ENCODING HELPERS (for creating encrypted strings)
; =============================================================================

; Encode a string with simple XOR (for creating encrypted commands)
; Input: rdi = source string, rsi = destination buffer
encode_simple_xor:
    push rdx
    
.encode_loop:
    mov al, [rdi]            ; Get source byte
    test al, al              ; Check for null terminator
    jz .encode_done          ; If null, we're done
    xor al, 0xAA             ; Encode byte (XOR with 0xAA)
    mov [rsi], al            ; Store encoded byte
    inc rdi                  ; Move to next source byte
    inc rsi                  ; Move to next destination byte
    jmp .encode_loop         ; Continue loop
    
.encode_done:
    mov byte [rsi], 0        ; Add null terminator
    
    pop rdx
    ret

; =============================================================================
; USAGE EXAMPLES:
; =============================================================================
; 
; ; In your main code:
; section .data
;     my_encrypted_string db 0xc2, 0xcf, 0xc6, 0xc6, 0xc5, 0  ; "hello" XOR 0xAA
; 
; section .text
; _start:
;     ; Use default crypto (simple XOR)
;     mov rdi, my_encrypted_string
;     call copy_and_decode     ; rdi now points to "hello"
;     
;     ; Switch to multibyte XOR
;     mov rdi, 1
;     call set_crypto_method
;     
;     ; Now all decryption uses multibyte XOR
;     mov rdi, my_encrypted_string
;     call copy_and_decode
; =============================================================================
