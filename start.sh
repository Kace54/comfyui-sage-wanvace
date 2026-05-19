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
        if [ ! -d "custom_nodes/ComfyUI-Manager" ]; then
            git clone https://github.com/ltdrdata/ComfyUI-Manager.git ./custom_nodes/ComfyUI-Manager
        else
            cd custom_nodes/ComfyUI-Manager && (git pull --autostash || true) && cd ../..
        fi

        if [ ! -d "custom_nodes/RGThree-ComfyUI" ]; then
            git clone https://github.com/rgthree/rgthree-comfy.git ./custom_nodes/RGThree-ComfyUI
        else
            cd custom_nodes/RGThree-ComfyUI && (git pull --autostash || true) && cd ../..
        fi

        if [ ! -d "custom_nodes/ComfyUI-Wan-VACE-Prep" ]; then
            git clone https://github.com/stuttlepress/ComfyUI-Wan-VACE-Prep.git ./custom_nodes/ComfyUI-Wan-VACE-Prep
        else
            cd custom_nodes/ComfyUI-Wan-VACE-Prep && (git pull --autostash || true) && cd ../..
        fi

        if [ ! -d "custom_nodes/ComfyUI-KJNodes" ]; then
            git clone https://github.com/kijai/ComfyUI-KJNodes.git ./custom_nodes/ComfyUI-KJNodes
        else
            cd custom_nodes/ComfyUI-KJNodes && (git pull --autostash || true) && cd ../..
        fi

        if [ ! -d "custom_nodes/ComfyUI-VideoHelperSuite" ]; then
            git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git ./custom_nodes/ComfyUI-VideoHelperSuite
        else
            cd custom_nodes/ComfyUI-VideoHelperSuite && (git pull --autostash || true) && cd ../..
        fi

        if [ ! -d "custom_nodes/ComfyUI-basic_data_handling" ]; then
            git clone https://github.com/StableLlama/ComfyUI-basic_data_handling.git ./custom_nodes/ComfyUI-basic_data_handling
        else
            cd custom_nodes/ComfyUI-basic_data_handling && (git pull --autostash || true) && cd ../..
        fi
		
        if [ ! -d "custom_nodes/ComfyUI-mxToolkit" ]; then
            git clone https://github.com/Smirnov75/ComfyUI-mxToolkit.git ./custom_nodes/ComfyUI-mxToolkit
        else
            cd custom_nodes/ComfyUI-mxToolkit && (git pull --autostash || true) && cd ../..
        fi
		
		if [ ! -d "custom_nodes/ComfyUI-SageAttention" ]; then
			git clone https://github.com/Tps-F/ComfyUI-SageAttention.git ./custom_nodes/ComfyUI-SageAttention
		else
            cd custom_nodes/ComfyUI-SageAttention && (git pull --autostash || true) && cd ../..
		fi
    fi

    mkdir -p "models/diffusion_models/WAN 2.2/Fun"
    mkdir -p "models/loras/Wan 2.2/T2V"
    mkdir -p "models/text_encoders"

    echo "-- Installing custom nodes dependencies --"
    find /workspace/ComfyUI/custom_nodes -maxdepth 2 -name "requirements.txt" -exec pip install --no-cache-dir -r {} \;

    echo "-- ComfyUI setup completed! --"
}

install_sage_attention() {
    if [ -n "$DISABLE_SAGE" ] && [ "$DISABLE_SAGE" == "true" ]; then
        echo "-- SageAttention disabled, skipping install --"
        return
    fi
    echo "-- Installing SageAttention (requires GPU, done at runtime) --"
    pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git
    echo "-- SageAttention installed --"
}

start_comfyui() {
    echo "-- Starting ComfyUI --"
    cd /workspace/ComfyUI

    if [ -n "$DISABLE_SAGE" ] && [ "$DISABLE_SAGE" == "true" ]; then
        nohup python main.py --fast fp16_accumulation --listen 0.0.0.0 \
            &> /workspace/comfyui.log &
        echo "-- SageAttention disabled --"
    else
        nohup python main.py --fast fp16_accumulation --use-sage-attention --listen 0.0.0.0 \
            &> /workspace/comfyui.log &
    fi

    echo "-- ComfyUI started --"
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
        wget -q --show-progress \
            "${VAE_URL}" \
            -O "${VAE_DIR}/wan_2.1_vae.safetensors" &
        PIDS+=(${!})
    else
        echo "-- wan_2.1_vae already exists, skipping --"
    fi

    DIFF_DIR="models/diffusion_models/WAN 2.2/Fun"
    DIFF_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models"

    if [[ ! -f "${DIFF_DIR}/wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" ]]; then
        echo "-- Downloading wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors (17 GB) --"
        wget -q --show-progress \
            "${DIFF_BASE}/wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" \
            -O "${DIFF_DIR}/wan2.2_fun_vace_high_noise_14B_fp8_scaled.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_fun_vace_high_noise already exists, skipping --"
    fi

    if [[ ! -f "${DIFF_DIR}/wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" ]]; then
        echo "-- Downloading wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors (17 GB) --"
        wget -q --show-progress \
            "${DIFF_BASE}/wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" \
            -O "${DIFF_DIR}/wan2.2_fun_vace_low_noise_14B_fp8_scaled.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_fun_vace_low_noise already exists, skipping --"
    fi

    LORA_DIR="models/loras/Wan 2.2/T2V"
    LORA_BASE="https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main"

    if [[ ! -f "${LORA_DIR}/wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" ]]; then
        echo "-- Downloading wan2.2_t2v_A14b_high_noise_lora (586 MB) --"
        wget -q --show-progress \
            "${LORA_BASE}/wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" \
            -O "${LORA_DIR}/wan2.2_t2v_A14b_high_noise_lora_rank64_lightx2v_4step_1217.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_t2v_A14b_high_noise_lora already exists, skipping --"
    fi

    if [[ ! -f "${LORA_DIR}/wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" ]]; then
        echo "-- Downloading wan2.2_t2v_A14b_low_noise_lora (586 MB) --"
        wget -q --show-progress \
            "${LORA_BASE}/wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" \
            -O "${LORA_DIR}/wan2.2_t2v_A14b_low_noise_lora_rank64_lightx2v_4step_1217.safetensors" &
        PIDS+=($!)
    else
        echo "-- wan2.2_t2v_A14b_low_noise_lora already exists, skipping --"
    fi

    ENC_DIR="models/text_encoders"
    ENC_BASE="https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders"

    if [[ ! -f "${ENC_DIR}/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ]]; then
        echo "-- Downloading umt5_xxl_fp8_e4m3fn_scaled.safetensors (6.3 GB) --"
        wget -q --show-progress \
            "${ENC_BASE}/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
            -O "${ENC_DIR}/umt5_xxl_fp8_e4m3fn_scaled.safetensors" &
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

echo "> Start script finished, Pod is ready to use. <"
tail -f /workspace/comfyui.log
