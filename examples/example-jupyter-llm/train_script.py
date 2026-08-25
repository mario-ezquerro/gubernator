#!/usr/bin/env python3
"""
Gubernator LLM Fine-Tuning Script using Hugging Face TRL (SFTTrainer) & PEFT (LoRA)
Supports both CPU (ARM64/AMD64) and GPU (NVIDIA CUDA).
"""

import os
import torch
from datasets import Dataset
from transformers import AutoModelForCausalLM, AutoTokenizer, TrainingArguments
from peft import LoraConfig, get_peft_model, TaskType
from trl import SFTTrainer

# 1. Configuration
MODEL_ID = os.getenv("BASE_MODEL", "HuggingFaceTB/SmolLM-135M-Instruct")
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/home/jovyan/work/output/gubernator-smollm-lora")
NUM_EPOCHS = int(os.getenv("NUM_EPOCHS", "3"))
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

print(f"🚀 Initializing LLM Fine-Tuning Pipeline...")
print(f"   Base Model : {MODEL_ID}")
print(f"   Device     : {DEVICE} (Torch Version: {torch.__version__})")
print(f"   Output Dir : {OUTPUT_DIR}")

# 2. Sample Gubernator Domain Dataset
training_data = [
    {
        "prompt": "¿Qué es Gubernator y en qué se diferencia de Kubernetes y Nomad?",
        "response": "Gubernator (gbnt) es un orquestador 'Goldilocks' que combina la simplicidad de Docker Swarm con la potencia y flexibilidad de Nomad. A diferencia de Kubernetes, no requiere un plano de control complejo ni etcd pesado; funciona con una base de datos SQLite distribuida, API REST segura, Caddy Ingress multihost automático, almacenamiento distribuido con GlusterFS y un dashboard web moderno en Flutter."
    },
    {
        "prompt": "¿Cómo se despliega una aplicación usando Docker Compose en un clúster de Gubernator?",
        "response": "Para desplegar una aplicación en Gubernator, escribe tu archivo docker-compose.yml con las restricciones de hardware deseadas en deploy.placement.constraints y ejecuta: `gbnt stack deploy -c docker-compose.yml nombre-del-stack`. Gubernator programará los contenedores en los nodos óptimos y configurará automáticamente el enrutamiento Ingress y DNS."
    },
    {
        "prompt": "¿Cómo se realiza un respaldo seguro y consistente de una base de datos en Gubernator?",
        "response": "Para hacer un backup con 100% de consistencia transaccional, usa el comando: `gbnt backup create --name backup-postgres --source /var/contenedores/postgres --pause`. La opción --pause congela temporalmente el contenedor durante el archivado .tar.gz para evitar escrituras concurrentes y calcula un hash criptográfico SHA-256."
    },
    {
        "prompt": "¿Cómo se añaden etiquetas de hardware para dirigir contenedores a nodos con GPU?",
        "response": "Puedes etiquetar un nodo Centurion con: `gbnt node label add node-worker1 gbnt.node.gpu=nvidia gbnt.node.zone=europe-1`. Luego, en tu compose.yml, añade la restricción: `node.labels.gbnt.node.gpu == nvidia` para garantizar que la tarea se ejecute en el servidor con aceleración GPU."
    },
    {
        "prompt": "¿Cómo se monitorea la salud y observabilidad del clúster Gubernator?",
        "response": "Gubernator integra de forma nativa la suite SRE completa accesible con `gbnt monitor init`: Prometheus para métricas de CPU/RAM/Disco, Grafana para paneles ejecutivos en el puerto 3000, Loki y Promtail para agregación centralizada de logs en tiempo real, y Jaeger para tracing distribuido OTLP."
    }
]

# Format as chat/instruction dataset
formatted_dataset = []
for item in training_data:
    formatted_dataset.append({
        "text": f"<|im_start|>user\n{item['prompt']}<|im_end|>\n<|im_start|>assistant\n{item['response']}<|im_end|>"
    })

dataset = Dataset.from_list(formatted_dataset)
print(f"📊 Loaded {len(dataset)} training examples into Hugging Face Dataset.")

# 3. Load Tokenizer & Base Model
print("📦 Loading Base Tokenizer & Model...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
if tokenizer.pad_token is None:
    tokenizer.pad_token = tokenizer.eos_token

model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    torch_dtype=torch.float32 if DEVICE == "cpu" else torch.float16,
    trust_remote_code=True,
)

# 4. Configure LoRA (Low-Rank Adaptation)
peft_config = LoraConfig(
    task_type=TaskType.CAUSAL_LM,
    r=8,
    lora_alpha=16,
    lora_dropout=0.05,
    bias="none",
    target_modules=["q_proj", "v_proj"]
)

model = get_peft_model(model, peft_config)
model.print_trainable_parameters()

# 5. Training Arguments
training_args = TrainingArguments(
    output_dir=OUTPUT_DIR,
    num_train_epochs=NUM_EPOCHS,
    per_device_train_batch_size=1,
    gradient_accumulation_steps=2,
    learning_rate=2e-4,
    logging_steps=1,
    save_strategy="epoch",
    optim="adamw_torch",
    report_to="none",
    use_cpu=(DEVICE == "cpu")
)

# 6. Initialize SFTTrainer & Train
trainer = SFTTrainer(
    model=model,
    train_dataset=dataset,
    peft_config=peft_config,
    dataset_text_field="text",
    max_seq_length=512,
    tokenizer=tokenizer,
    args=training_args,
)

print("⚡ Starting Fine-Tuning Execution...")
trainer.train()

# 7. Save Final LoRA Weights
print(f"💾 Saving trained LoRA adapter weights to: {OUTPUT_DIR}")
trainer.model.save_pretrained(OUTPUT_DIR)
tokenizer.save_pretrained(OUTPUT_DIR)
print("🎉 Fine-Tuning Pipeline completed successfully!")

# 8. Quick Inference Test
print("\n🧪 Running Post-Training Inference Verification...")
test_prompt = "<|im_start|>user\n¿Qué es Gubernator y para qué sirve?<|im_end|>\n<|im_start|>assistant\n"
inputs = tokenizer(test_prompt, return_tensors="pt").to(DEVICE)
with torch.no_grad():
    outputs = trainer.model.generate(
        **inputs,
        max_new_tokens=100,
        temperature=0.7,
        do_sample=True,
        pad_token_id=tokenizer.eos_token_id
    )

response = tokenizer.decode(outputs[0], skip_special_tokens=False)
print("🤖 Model Response:\n", response)
