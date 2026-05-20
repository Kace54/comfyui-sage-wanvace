#!/bin/bash
set -e

# ----------------------------------------------------------------------------
#                          Function Definitions
# ----------------------------------------------------------------------------

start_nginx() {
    echo "-- Starting Nginx service --"
    service nginx start
    echo "-- Nginx service started --"
}

execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

setup_ssh() {
    if [[ $PUBLIC_KEY ]]; then
        echo "-- Setting up SSH --"
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh

        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
            echo "RSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub
        fi
        if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
            ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
            echo "ECDSA key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub
        fi
        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
            echo "ED25519 key fingerprint:"
            ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
        fi

        echo "-- SSH host keys --"
        for key in /etc/ssh/*.pub; do
            echo "Key: $key"
            ssh-keygen -lf $key
        done

        echo "-- Starting SSH service --"
        service ssh start
        echo "-- SSH service started --"
    fi
}

export_env_vars() {
    echo "-- Exporting environment variables --"
    printenv | grep -E '^[A-Z_][A-Z0-9_]*=' | grep -v '^PUBLIC_KEY' | \
        awk -F = '{ val = $0; sub(/^[^=]*=/, "", val); print "export " $1 "=\"" val "\"" }' \
        > /etc/rp_environment
    if ! grep -q 'source /etc/rp_environment' ~/.bashrc; then
        echo 'source /etc/rp_environment' >> ~/.bashrc
    fi
}

start_jupyter() {
    if [[ $JUPYTER_PASSWORD ]]; then
        echo "-- Starting Jupyter Lab --"
        mkdir -p /workspace && cd /
        nohup python3 -m jupyter lab \
            --allow-root \
            --no-browser \
            --port=8888 \
            --ip=* \
            --FileContentsManager.delete_to_trash=False \
            --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
            --IdentityProvider.token=$JUPYTER_PASSWORD \
            --ServerApp.allow_origin=* \
            --ServerApp.preferred_dir=/workspace \
            &> /jupyter.log &
        echo "-- Jupyter Lab started --"
    fi
}

# ----------------------------------------------------------------------------
#                        ComfyUI Specific Functions
# ----------------------------------------------------------------------------

setup_comfyui() {
    echo "-- Setting up ComfyUI --"
    cd /workspace

    if [ -f "/workspace/.setup_done" ] && [ "$FORCE_UPDATE" != "true" ]; then
        echo "-- Fast boot: .setup_done flag found. Skipping ComfyUI git pulls & pip installs. --"
        return
    fi

    if [ ! -d "ComfyUI" ]; then
        echo "-- Cloning ComfyUI --"
        git clone https://github.com/comfyanonymous/ComfyUI.git
    else
        echo "-- Updating ComfyUI --"
        cd ComfyUI && (git pull --autostash || true) && cd ..
    fi

    cd ComfyUI

    if [ -n "$DISABLE_CUSTOM" ] && [ "$DISABLE_CUSTOM" = "true" ]; then
        echo "-- Custom nodes disabled --"
    else
        echo "-- Parallel cloning/updating of custom nodes --"
        PIDS_NODES=()
        
        clone_or_update() {
            local repo_url=$1
            local target_dir=$2
            if [ ! -d "$target_dir" ]; then
                git clone "$repo_url" "$target_dir"
            else
                cd "$target_dir" && (git pull --autostash || true) && cd ../..
            fi
        }

        clone_or_update "https://github.com/ltdrdata/ComfyUI-Manager.git" "./custom_nodes/ComfyUI-Manager" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/rgthree/rgthree-comfy.git" "./custom_nodes/RGThree-ComfyUI" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/stuttlepress/ComfyUI-Wan-VACE-Prep.git" "./custom_nodes/ComfyUI-Wan-VACE-Prep" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/kijai/ComfyUI-KJNodes.git" "./custom_nodes/ComfyUI-KJNodes" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "./custom_nodes/ComfyUI-VideoHelperSuite" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/StableLlama/ComfyUI-basic_data_handling.git" "./custom_nodes/ComfyUI-basic_data_handling" & PIDS_NODES+=($!)
        clone_or_update "https://github.com/Smirnov75/ComfyUI-mxToolkit.git" "./custom_nodes/ComfyUI-mxToolkit" & PIDS_NODES+=($!)

        wait "${PIDS_NODES[@]}"
    fi

    mkdir -p "models/diffusion_models/WAN 2.2/Fun"
    mkdir -p "models/loras/Wan 2.2/T2V"
    mkdir -p "models/text_encoders"

    echo "-- Installing custom nodes dependencies --"
    find /workspace/ComfyUI/custom_nodes -maxdepth 2 -name "requirements.txt" -exec uv pip install --system --no-cache -r {} \;

    echo "-- ComfyUI setup completed! --"
}

install_sage_attention() {
    if [ -n "$DISABLE_SAGE" ] && [ "$DISABLE_SAGE" == "true" ]; then
        echo "-- SageAttention disabled, skipping install --"
        return
    fi
    if python -c "import sageattention" &>/dev/null; then
        echo "-- SageAttention is already installed --"
        return
    fi
    echo "-- Installing SageAttention (precompiled wheel) --"
    pip install --no-cache-dir https://github.com/Kace54/comfyui-sage-wanvace/releases/download/v2.2.0/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
    echo "-- SageAttention installed --"
}

start_comfyui() {
    echo "-- Starting ComfyUI --"
    cd /workspace/ComfyUI

    (
        while true; do
            echo "-- Launching ComfyUI --" >> /workspace/comfyui.log
            if [ -n "$DISABLE_SAGE" ] && [ "$DISABLE_SAGE" == "true" ]; then
                echo "-- SageAttention disabled --" >> /workspace/comfyui.log
                python main.py --fast fp16_accumulation --listen 0.0.0.0 >> /workspace/comfyui.log 2>&1
            else
                python main.py --fast fp16_accumulation --use-sage-attention --listen 0.0.0.0 >> /workspace/comfyui.log 2>&1
            fi
            
            EXIT_CODE=$?
            echo "-- ComfyUI exited with code $EXIT_CODE --" >> /workspace/comfyui.log
            
            if [ $EXIT_CODE -eq 0 ]; then
                echo "-- Clean exit (code 0). Stopping auto-restart. --" >> /workspace/comfyui.log
                break
            fi
            
            echo "-- ComfyUI crashed (possible OOM). Restarting in 5 seconds... --" >> /workspace/comfyui.log
            sleep 5
        done
    ) &

    echo "-- ComfyUI started (with auto-restart) --"
}

# ----------------------------------------------------------------------------
#                        WAN VACE Model Downloads
# ----------------------------------------------------------------------------

download_wan_vace_models() {
    echo "-- Downloading WAN VACE models --"
    cd /workspace/ComfyUI

    if [ -n "$HF_TOKEN" ]; then
        echo "-- Logging into Hugging Face --"
        hf auth login --token $HF_TOKEN
    fi

    PIDS=()
    
    # --- WAN 2.1 VAE ---
    VAE_DIR="models/vae"
    VAE_URL="https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
    if [[ ! -f "${VAE_DIR}/wan_2.1_vae.safetensors" ]]; then
        echo "-- Downloading wan_2.1_vae.safetensors (254 MB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${VAE_URL}" \
            -d "${VAE_DIR}" -o "wan_2.1_vae.safetensors" &
        PIDS+=(${!})
    else
        echo "-- wan_2.1_vae already exists, skipping --"
    fi

    DIFF_DIR="models/diffusion_models/WAN 2.2/Fun"
    DIFF_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models"

    if [[ ! -f "${DIFF_DIR}/wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" ]]; then
        echo "-- Downloading wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors (17 GB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${DIFF_BASE}/wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" \
            -d "${DIFF_DIR}" -o "wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_fun_vace_high_noise already exists, skipping --"
    fi

    if [[ ! -f "${DIFF_DIR}/wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" ]]; then
        echo "-- Downloading wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors (17 GB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${DIFF_BASE}/wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" \
            -d "${DIFF_DIR}" -o "wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_fun_vace_low_noise already exists, skipping --"
    fi

    LORA_DIR="models/loras/Wan 2.2/T2V"
    LORA_BASE="https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main"

    if [[ ! -f "${LORA_DIR}/wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" ]]; then
        echo "-- Downloading wan2.2_t2v_A14b_high_noise_lora (586 MB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${LORA_BASE}/wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" \
            -d "${LORA_DIR}" -o "wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_t2v_A14b_high_noise_lora already exists, skipping --"
    fi

    if [[ ! -f "${LORA_DIR}/wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" ]]; then
        echo "-- Downloading wan2.2_t2v_A14b_low_noise_lora (586 MB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${LORA_BASE}/wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" \
            -d "${LORA_DIR}" -o "wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_t2v_A14b_low_noise_lora already exists, skipping --"
    fi

    ENC_DIR="models/text_encoders"
    ENC_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders"

    if [[ ! -f "${ENC_DIR}/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ]]; then
        echo "-- Downloading umt5_xxl_fp8_e4m3fn_scaled.safetensors (6.3 GB) --"
        aria2c -x 16 -s 16 -k 1M --console-log-level=error --summary-interval=10 \
            "${ENC_BASE}/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
            -d "${ENC_DIR}" -o "umt5_xxl_fp8_e4m3fn_scaled.safetensors" &
        PIDS+=($!)
    else
        echo "-- umt5_xxl_fp8_e4m3fn_scaled already exists, skipping --"
    fi

    # Attendre la fin de tous les téléchargements
    if [[ ${#PIDS[@]} -gt 0 ]]; then
        echo "-- Waiting for all downloads to complete (~40 GB total) --"
        wait "${PIDS[@]}"
    fi

    echo "-- All WAN VACE downloads completed! --"
}

# ----------------------------------------------------------------------------
#                              Main Program
# ----------------------------------------------------------------------------

start_nginx
execute_script "/pre_start.sh" "Running pre-start script..."
echo "> Pod Started <"

# Startup de base
setup_ssh
start_jupyter
export_env_vars

# ComfyUI specific startup
setup_comfyui
install_sage_attention
download_wan_vace_models
start_comfyui

# Write fast boot flag so next restart is instant
if [ "$FORCE_UPDATE" != "true" ]; then
    touch "/workspace/.setup_done"
fi

echo "> Start script finished, Pod is ready to use. <"
tail -f /workspace/comfyui.log
