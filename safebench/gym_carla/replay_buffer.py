'''
Date: 2023-01-31 22:23:17
LastEditTime: 2023-04-03 21:37:36
Description: 
    Copyright (c) 2022-2023 Safebench Team

    This work is licensed under the terms of the MIT license.
    For a copy, see <https://opensource.org/licenses/MIT>
'''

import numpy as np
import torch


def _sample_replay_indices(candidates, size):
    if size <= 0:
        return np.array([], dtype=int)
    if len(candidates) == 0:
        return np.array([], dtype=int)
    replace = len(candidates) < size
    return np.random.choice(candidates, size=size, replace=replace)


def _concat_selected(parts):
    parts = [part for part in parts if part is not None and len(part) > 0]
    if not parts:
        return np.array([])
    if len(parts) == 1:
        return parts[0]
    return np.concatenate(parts)


class RouteReplayBuffer:
    """
        This buffer supports parallel storing transitions from multiple trajectories.
    """
    
    def __init__(self, num_scenario, mode, buffer_capacity=1000):
        self.mode = mode
        ## by defualt, the buffer_capacity for collision buffer is 1/100 of buffer_capacity
        self.buffer_capacity = buffer_capacity
        self.num_scenario = num_scenario
        self.buffer_len = 0
        self.collision_buffer_len = 0
        # buffers for step info
        self.reset_buffer()

        # buffers for init info
        self.reset_init_buffer()

    def reset_buffer(self):
        self.buffer_ego_actions = [[] for _ in range(self.num_scenario)]
        self.buffer_scenario_actions = [[] for _ in range(self.num_scenario)]
        self.buffer_obs = [[] for _ in range(self.num_scenario)]
        self.buffer_next_obs = [[] for _ in range(self.num_scenario)]
        self.buffer_rewards = [[] for _ in range(self.num_scenario)]
        self.buffer_dones = [[] for _ in range(self.num_scenario)]
        self.buffer_additional_dict = [{} for _ in range(self.num_scenario)]

        self.collision_buffer_ego_actions = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_scenario_actions = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_obs = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_next_obs = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_rewards = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_dones = [[] for _ in range(self.num_scenario)]
        self.collision_buffer_additional_dict = [{} for _ in range(self.num_scenario)]
        
    def reset_init_buffer(self):
        self.buffer_static_obs = []
        self.buffer_init_action = []
        self.buffer_episode_reward = []
        self.buffer_init_additional_dict = {}
        self.init_buffer_len = 0

    def save_buffer(self, path):
        torch.save({
            'buffer_ego_actions': self.buffer_ego_actions,
            'buffer_scenario_actions': self.buffer_scenario_actions,
            'buffer_next_obs': self.buffer_next_obs,
            'buffer_obs': self.buffer_obs,
            'buffer_rewards': self.buffer_rewards,
            'buffer_dones': self.buffer_dones,
            'buffer_additional_dict': self.buffer_additional_dict,
            'collision_buffer_ego_actions': self.collision_buffer_ego_actions,
            'collision_buffer_scenario_actions': self.collision_buffer_scenario_actions,
            'collision_buffer_next_obs': self.collision_buffer_next_obs,
            'collision_buffer_obs': self.collision_buffer_obs,
            'collision_buffer_rewards': self.collision_buffer_rewards,
            'collision_buffer_dones': self.collision_buffer_dones,
            'collision_buffer_additional_dict': self.collision_buffer_additional_dict,
            'buffer_static_obs': self.buffer_static_obs,
            'buffer_init_action': self.buffer_init_action,
            'buffer_episode_reward': self.buffer_episode_reward,
            'buffer_init_additional_dict': self.buffer_init_additional_dict,
            'buffer_len': self.buffer_len,
            'collision_buffer_len': self.collision_buffer_len,
            'init_buffer_len': self.init_buffer_len
        }, path)
 
    def load_buffer(self, path):
        data = torch.load(path)
        self.buffer_ego_actions = data['buffer_ego_actions']
        self.buffer_scenario_actions = data['buffer_scenario_actions']
        self.buffer_next_obs = data['buffer_next_obs']
        self.buffer_obs = data['buffer_obs']
        self.buffer_rewards = data['buffer_rewards']
        self.buffer_dones = data['buffer_dones']
        self.buffer_additional_dict = data['buffer_additional_dict']
        self.collision_buffer_ego_actions = data['collision_buffer_ego_actions']
        self.collision_buffer_scenario_actions = data['collision_buffer_scenario_actions']
        self.collision_buffer_next_obs = data['collision_buffer_next_obs']
        self.collision_buffer_obs = data['collision_buffer_obs']
        self.collision_buffer_rewards = data['collision_buffer_rewards']
        self.collision_buffer_dones = data['collision_buffer_dones']
        self.collision_buffer_additional_dict = data['collision_buffer_additional_dict']
        self.buffer_static_obs = data['buffer_static_obs']
        self.buffer_init_action = data['buffer_init_action']
        self.buffer_episode_reward = data['buffer_episode_reward']
        self.buffer_init_additional_dict = data['buffer_init_additional_dict']
        self.buffer_len = data['buffer_len']
        self.collision_buffer_len = data['collision_buffer_len']
        self.init_buffer_len = data['init_buffer_len']

    def finish_one_episode(self):
        # get total reward for episode
        for s_i in range(self.num_scenario):
            try:
                dones = np.where(self.buffer_dones[s_i])[0]
                start_ = dones[-2] if len(dones) > 1 else -1
                end_ = dones[-1]
                self.buffer_episode_reward.append(np.sum(self.buffer_rewards[s_i][start_+1:end_+1]))
            except:
                pass

    def store(self, data_list, additional_dict):
        ego_actions = data_list[0]
        scenario_actions = data_list[1]
        obs = data_list[2]
        next_obs = data_list[3]
        rewards = data_list[4]
        dones = data_list[5]

        # separate trajectories according to infos
        for s_i in range(len(additional_dict)):
            sid = additional_dict[s_i]['scenario_id']
            if additional_dict[s_i]['collision']:
                self.collision_buffer_ego_actions[sid].append(ego_actions[s_i])
                self.collision_buffer_scenario_actions[sid].append(scenario_actions[s_i])
                self.collision_buffer_obs[sid].append(obs[s_i])
                self.collision_buffer_next_obs[sid].append(next_obs[s_i])
                self.collision_buffer_rewards[sid].append(rewards[s_i])
                self.collision_buffer_dones[sid].append(dones[s_i])
                # store additional information in given dict (e.g., cost and actor_info)
                for key in additional_dict[s_i].keys():
                    if key in ['scenario_id', 'route_waypoints', 'actor_info']:
                        continue
                    if key not in self.collision_buffer_additional_dict[s_i].keys():
                        self.collision_buffer_additional_dict[s_i][key] = []
                    self.collision_buffer_additional_dict[s_i][key].append(additional_dict[s_i][key])
                self.collision_buffer_len += 1
            else:
                self.buffer_ego_actions[sid].append(ego_actions[s_i])
                self.buffer_scenario_actions[sid].append(scenario_actions[s_i])
                self.buffer_obs[sid].append(obs[s_i])
                self.buffer_next_obs[sid].append(next_obs[s_i])
                self.buffer_rewards[sid].append(rewards[s_i])
                self.buffer_dones[sid].append(dones[s_i])
                # store additional information in given dict (e.g., cost and actor_info)
                for key in additional_dict[s_i].keys():
                    if key in ['scenario_id', 'route_waypoints', 'actor_info']:
                        continue
                    if key not in self.buffer_additional_dict[s_i].keys():
                        self.buffer_additional_dict[s_i][key] = []
                    self.buffer_additional_dict[s_i][key].append(additional_dict[s_i][key])
                self.buffer_len += 1

    def store_init(self, data_list, additional_dict=None):
        static_obs = data_list[0]
        scenario_init_action = data_list[1]
        self.buffer_static_obs.append(static_obs)
        self.buffer_init_action.append(scenario_init_action)
        self.init_buffer_len += len(scenario_init_action)

        # store additional information in given dict
        if additional_dict:
            for key in additional_dict.keys():
                if key in ['route_waypoints', 'actor_info']:
                        continue
                if key not in self.buffer_init_additional_dict.keys():
                    self.buffer_init_additional_dict[key] = []
                self.buffer_init_additional_dict[key].append(additional_dict[key])

    def sample_init(self, batch_size):
        num_trajectory = len(self.buffer_init_action)
        start_idx = np.max([0, num_trajectory - self.buffer_capacity]) 

        # select up-to-date samples from buffer
        prepared_static_obs = self.buffer_static_obs[start_idx:]
        prepared_init_action = self.buffer_init_action[start_idx:]
        prepared_episode_reward = self.buffer_episode_reward[start_idx:]

        # sample action and episode reward
        sample_index = np.random.randint(0, len(prepared_init_action), size=batch_size)
        static_obs = np.concatenate(prepared_static_obs, axis=0)[sample_index]
        init_action = np.concatenate(prepared_init_action, axis=0)[sample_index]
        episode_reward = np.array(prepared_episode_reward)[sample_index]
        batch = {
            'static_obs': static_obs,
            'init_action': init_action,
            'episode_reward': episode_reward,
        }

        # add additional information to the batch (assume with torch)
        for key in self.buffer_init_additional_dict.keys():
            batch[key] = torch.cat(self.buffer_init_additional_dict[key][start_idx:])[sample_index]
        return batch

    def sample(self, batch_size):
        # prepare concatenated list
        prepared_ego_actions = []
        prepared_scenario_actions = []
        prepared_obs = []
        prepared_next_obs = []
        prepared_rewards = []
        prepared_dones = []
        prepared_infos = {}

        prepared_collision_ego_actions = []
        prepared_collision_scenario_actions = []
        prepared_collision_obs = []
        prepared_collision_next_obs = []
        prepared_collision_rewards = []
        prepared_collision_dones = []
        prepared_collision_infos = {}
        
        # get the length of each sub-buffer
        samples_per_trajectory = self.buffer_capacity // self.num_scenario # assume average over all sub-buffer
        for s_i in range(self.num_scenario):
            # select the latest samples starting from the end of buffer
            start_idx = np.max([0, len(self.buffer_rewards[s_i]) - samples_per_trajectory])
            # the buffer size for collision size is the buffer of the non-collision // 100
            collision_start_idx = np.max([0, len(self.collision_buffer_rewards[s_i]) - samples_per_trajectory//100])
            
            # concat
            prepared_ego_actions += self.buffer_ego_actions[s_i][start_idx:]
            prepared_scenario_actions += self.buffer_scenario_actions[s_i][start_idx:]
            prepared_obs += self.buffer_obs[s_i][start_idx:]
            prepared_next_obs += self.buffer_next_obs[s_i][start_idx:]
            prepared_rewards += self.buffer_rewards[s_i][start_idx:]
            prepared_dones += self.buffer_dones[s_i][start_idx:]

            prepared_collision_ego_actions += self.collision_buffer_ego_actions[s_i][collision_start_idx:]
            prepared_collision_scenario_actions += self.collision_buffer_scenario_actions[s_i][collision_start_idx:]
            prepared_collision_obs += self.collision_buffer_obs[s_i][collision_start_idx:]
            prepared_collision_next_obs += self.collision_buffer_next_obs[s_i][collision_start_idx:]
            prepared_collision_rewards += self.collision_buffer_rewards[s_i][collision_start_idx:]
            prepared_collision_dones += self.collision_buffer_dones[s_i][collision_start_idx:]

            # add additional information 
            for k_i in self.buffer_additional_dict[s_i].keys():
                if k_i not in prepared_infos.keys():
                    prepared_infos[k_i] = []
                prepared_infos[k_i] += self.buffer_additional_dict[s_i][k_i][start_idx:]
            
            for k_i in self.collision_buffer_additional_dict[s_i].keys():
                if k_i not in prepared_collision_infos.keys():
                    prepared_collision_infos[k_i] = []
                prepared_collision_infos[k_i] += self.collision_buffer_additional_dict[s_i][k_i][collision_start_idx:]

        # sample from concatenated list
        # the first sample does not have previous state ()
            
        sample_candidates = np.arange(1, len(prepared_rewards))
        collision_candidates = np.arange(1, len(prepared_collision_rewards))
        if len(sample_candidates) == 0 and len(collision_candidates) == 0:
            raise ValueError('Replay buffer does not contain enough transitions to sample.')

        if len(sample_candidates) == 0:
            sample_count = 0
            collision_count = batch_size
        elif len(collision_candidates) == 0:
            sample_count = batch_size
            collision_count = 0
        else:
            collision_count = batch_size // 5
            sample_count = batch_size - collision_count

        sample_index = _sample_replay_indices(sample_candidates, sample_count)
        collision_sample_index = _sample_replay_indices(collision_candidates, collision_count)

        # prepare batch 
        action = prepared_ego_actions if self.mode == 'train_agent' else prepared_scenario_actions
        collision_action = prepared_collision_ego_actions if self.mode == 'train_agent' else prepared_collision_scenario_actions

        batch = {
            'action': _concat_selected([
                np.stack(action)[sample_index] if len(sample_index) else None,
                np.stack(collision_action)[collision_sample_index] if len(collision_sample_index) else None,
            ]),
            'state': _concat_selected([
                np.stack(prepared_obs)[sample_index, :] if len(sample_index) else None,
                np.stack(prepared_collision_obs)[collision_sample_index] if len(collision_sample_index) else None,
            ]),
            'n_state': _concat_selected([
                np.stack(prepared_next_obs)[sample_index, :] if len(sample_index) else None,
                np.stack(prepared_collision_next_obs)[collision_sample_index] if len(collision_sample_index) else None,
            ]),
            'reward': _concat_selected([
                np.stack(prepared_rewards)[sample_index] if len(sample_index) else None,
                np.stack(prepared_collision_rewards)[collision_sample_index] if len(collision_sample_index) else None,
            ]),
            'done': _concat_selected([
                np.stack(prepared_dones)[sample_index] if len(sample_index) else None,
                np.stack(prepared_collision_dones)[collision_sample_index] if len(collision_sample_index) else None,
            ]),
        }

        # add additional information to the batch
        batch_info = {} 
        for k_i in set(prepared_infos.keys()) | set(prepared_collision_infos.keys()):
            if k_i in ['route_waypoints', 'actor_info']:
                continue
            info_parts = []
            next_info_parts = []
            if len(sample_index) and k_i in prepared_infos:
                info_values = np.stack(prepared_infos[k_i])
                info_parts.append(info_values[sample_index-1])
                next_info_parts.append(info_values[sample_index])
            if len(collision_sample_index) and k_i in prepared_collision_infos:
                collision_info_values = np.stack(prepared_collision_infos[k_i])
                info_parts.append(collision_info_values[collision_sample_index-1])
                next_info_parts.append(collision_info_values[collision_sample_index])
            if info_parts:
                batch_info[k_i] = _concat_selected(info_parts)
                batch_info['n_' + k_i] = _concat_selected(next_info_parts)
    
        # combine two dicts
        batch.update(batch_info)
        return batch


class PerceptionReplayBuffer:
    """
        This buffer supports parallel storing image states and labels for object detection
    """
    
    def __init__(self, num_scenario, mode, buffer_capacity=1000):
        self.mode = mode
        self.buffer_capacity = buffer_capacity
        self.num_scenario = num_scenario
        self.buffer_len = 0

        # buffers for different data type
        self.buffer_bbox_label = [[] for _ in range(num_scenario)]          # perception labels
        self.buffer_predictions = [[] for _ in range(num_scenario)]         # perception outputs
        self.buffer_scenario_actions = [[] for _ in range(num_scenario)]    # synthetic textures (attack)
        self.buffer_obs = [[] for _ in range(num_scenario)]                 # image observations (FPV observation)
        self.buffer_loss = [[] for _ in range(num_scenario)]                # object detection loss (IoU, class, etc.)
    
    def finish_one_episode(self):
        pass

    def reset_init_buffer(self):
        self.buffer_static_obs = []
        self.buffer_init_action = []
        self.buffer_episode_reward = []
        self.buffer_init_additional_dict = {}
        self.init_buffer_len = 0
    
    def store_init(self, data_list, additional_dict=None):
        pass
    
    def store(self, data_list, additional_dict=None):
        ego_actions = data_list[0]
        scenario_actions = data_list[1]
        obs = data_list[2]
        self.buffer_len += len(ego_actions)

        # separate trajectories according to infos
        for s_i in range(len(additional_dict)):
            sid = additional_dict[s_i]['scenario_id']
            self.buffer_predictions[sid].append(ego_actions[s_i]['od_result'])
            self.buffer_scenario_actions[sid].append(scenario_actions[s_i]['attack'])
            self.buffer_obs[sid].append(obs[s_i]['img'])
            self.buffer_bbox_label[sid].append(additional_dict[s_i]['bbox_label'])
            self.buffer_loss[sid].append(additional_dict[s_i]['iou_loss'])

    def sample(self, batch_size):
        # prepare concatenated list
        prepared_bbox_label = []
        prepared_predictions = []
        prepared_obs = []
        prepared_scenario_actions = []
        prepared_loss = []
        # get the length of each sub-buffer
        samples_per_trajectory = self.buffer_capacity // self.num_scenario # assume average over all sub-buffer
        for s_i in range(self.num_scenario):
            # select the latest samples starting from the end of buffer
            num_trajectory = len(self.buffer_loss[s_i])
            start_idx = np.max([0, num_trajectory - samples_per_trajectory])

            # concat
            prepared_bbox_label += self.buffer_bbox_label[s_i][start_idx:]
            prepared_predictions += self.buffer_predictions[s_i][start_idx:]
            prepared_scenario_actions += self.buffer_scenario_actions[s_i][start_idx:]
            prepared_obs += self.buffer_obs[s_i][start_idx:]
            prepared_loss += self.buffer_loss[s_i][start_idx:]
        # sample from concatenated list
        sample_index = np.random.randint(0, len(prepared_loss), size=batch_size)

        batch = {
            'label': np.stack(prepared_bbox_label)[sample_index, :],        
            # 'prediction': np.stack(prepared_predictions)[sample_index, :],     # TODO: Multiple/empty predictions should be stacked together
            # 'attack': np.stack(prepared_scenario_actions)[sample_index, :],
            # 'attack': torch.stack(prepared_scenario_actions)[sample_index, :],
            'image': np.stack(prepared_obs)[sample_index, :],
            'loss': np.stack(prepared_loss)[sample_index],                       # scalar with 1D 
        }
        
        return batch
