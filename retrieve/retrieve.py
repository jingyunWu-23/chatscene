try:
    import setGPU  # noqa: F401
except ImportError:
    pass
import csv
import pickle
import re
from os import path as osp
import argparse

# no need for faiss currently
# import faiss

parser = argparse.ArgumentParser(description="Set up configurations for your script.")
parser.add_argument('--port_ip', type=int, default=2000, help='Port IP address (default: 2000)')
parser.add_argument('--topk', type=int, default=3, help='Top K value (default: 3) for retrieval')
parser.add_argument('--model', type=str, default='qwen-plus', help="Model name (default: 'qwen-plus'), also support transformers model")
parser.add_argument('--llm_backend', type=str, default='auto', choices=['auto', 'openai', 'transformers'], help="LLM backend. Use 'openai' for OpenAI-compatible APIs and 'transformers' for local Hugging Face models.")
parser.add_argument('--api_key', type=str, default=None, help='API key for OpenAI-compatible APIs. Prefer setting OPENAI_API_KEY instead of passing secrets on the command line.')
parser.add_argument('--base_url', type=str, default=None, help='Optional OpenAI-compatible API base URL. Defaults to OPENAI_BASE_URL or the official OpenAI endpoint.')
parser.add_argument('--device', type=str, default='auto', help="Embedding device: 'auto', 'cuda', or 'cpu'.")
parser.add_argument('--use_env_proxy', action='store_true', help='Allow the OpenAI-compatible client to use HTTP_PROXY/HTTPS_PROXY/ALL_PROXY from the environment.')
parser.add_argument('--skip_compile', action='store_true', help='Only save generated Scenic files. Do not import CARLA or run ScenicSimulator compile checks.')
parser.add_argument('--use_llm', action='store_true', help='if use llm for generating new snippets')
args = parser.parse_args()

from tqdm import tqdm
from sentence_transformers import SentenceTransformer
import torch
from architecture import LLMChat
from utils import load_file, retrieve_topk, generate_code_snippet, save_scenic_code, render_spawn_code

port_ip = args.port_ip
topk = args.topk
use_llm = args.use_llm
device = 'cuda' if args.device == 'auto' and torch.cuda.is_available() else args.device
if device == 'auto':
    device = 'cpu'

llm_model = LLMChat(
    args.model,
    backend=args.llm_backend,
    api_key=args.api_key,
    base_url=args.base_url,
    trust_env=args.use_env_proxy,
)
local_path = osp.abspath(osp.dirname(osp.dirname(osp.realpath(__file__))))
extraction_prompt = load_file(osp.join(local_path, 'retrieve', 'prompts', 'extraction.txt'))
behavior_prompt = load_file(osp.join(local_path, 'retrieve', 'prompts', 'behavior.txt'))
geometry_prompt = load_file(osp.join(local_path, 'retrieve', 'prompts', 'geometry.txt'))
spawn_prompt = load_file(osp.join(local_path, 'retrieve', 'prompts', 'spawn.txt'))
scenario_descriptions = load_file(osp.join(local_path, 'retrieve', 'scenario_descriptions.txt')).split('\n')
encoder = SentenceTransformer('sentence-transformers/sentence-t5-large', device=device)

with open(osp.join(local_path, 'retrieve/database_v1.pkl'), 'rb') as file:
    database = pickle.load(file)
behavior_descriptions = database['behavior']['description']
geometry_descriptions = database['geometry']['description']
spawn_descriptions = database['spawn']['description']
behavior_snippets = database['behavior']['snippet']
geometry_snippets = database['geometry']['snippet']
spawn_snippets = database['spawn']['snippet']

behavior_embeddings = encoder.encode(behavior_descriptions, device=device, convert_to_tensor=True)
geometry_embeddings = encoder.encode(geometry_descriptions, device=device, convert_to_tensor=True)
spawn_embeddings = encoder.encode(spawn_descriptions, device=device, convert_to_tensor=True)

## this is the head for scenic file, you can modified the carla map or ego model here
head = '''param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"
'''

log_file_path = osp.join(local_path, 'safebench', 'scenario', 'scenario_data', 'scenic_data', 'dynamic_scenario', 'dynamic_log.csv')
with open(log_file_path, mode='w', newline='') as file:
    log_writer = csv.writer(file)
    log_writer.writerow(['Scenario', 'AdvObject', 'Behavior Description', 'Behavior Snippet', 'Geometry Description', 'Geometry Snippet', 'Spawn Description', 'Spawn Snippet', 'Success'])

    for q, current_scenario in tqdm(enumerate(scenario_descriptions)):
        messages=[
			{"role": "system", "content": "You are a helpful assistant."},
			{"role": "user", "content": extraction_prompt.format(scenario=current_scenario)},
			]
        response = llm_model.generate(messages)
        match = re.search(r"Adversarial Object:(.*?)Behavior:(.*?)Geometry:(.*?)Spawn Position:(.*)", response, re.DOTALL)
        # try:
        current_adv_object, current_behavior, current_geometry, current_spawn = [s.strip() for s in match.groups()]
        top_behavior_descriptions, top_behavior_snippets = retrieve_topk(encoder, topk, behavior_descriptions, behavior_snippets, behavior_embeddings, current_behavior, device)
        top_geometry_descriptions, top_geometry_snippets = retrieve_topk(encoder, topk, geometry_descriptions, geometry_snippets, geometry_embeddings, current_geometry, device)
        top_spawn_descriptions, top_spawn_snippets = retrieve_topk(encoder, topk, spawn_descriptions, spawn_snippets, spawn_embeddings, current_spawn, device)
        
        generated_behavior_code = generate_code_snippet(
            llm_model, behavior_prompt, top_behavior_descriptions, top_behavior_snippets, current_behavior, topk, use_llm
        )

        generated_geometry_code = generate_code_snippet(
            llm_model, geometry_prompt, top_geometry_descriptions, top_geometry_snippets, current_geometry, topk, use_llm
        )
        
        generated_spawn_code = generate_code_snippet(
            llm_model, spawn_prompt, top_spawn_descriptions, top_spawn_snippets, current_spawn, topk, use_llm
        )
        
        log_writer.writerow([current_scenario, current_adv_object, current_behavior, generated_behavior_code, current_geometry, generated_geometry_code, current_spawn, generated_spawn_code, 1])

        Town, generated_geometry_code = generated_geometry_code.split('\n', 1)
        rendered_spawn_code = render_spawn_code(generated_spawn_code, current_adv_object)
        scenic_code = '\n'.join([f"'''{current_scenario}'''", Town, head, generated_behavior_code, generated_geometry_code, rendered_spawn_code])
        save_scenic_code(local_path, port_ip, scenic_code, q, skip_compile=args.skip_compile)

        # except:
        #     log_writer.writerow([current_scenario, '', '', '', '', '', '', '', 0])
        #     print("Failure for scenario:", current_scenario)
