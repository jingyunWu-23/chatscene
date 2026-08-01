import inspect


def save_policy_model(policy, episode, replay_buffer=None):
    """Save policies with either save_model(episode) or save_model(episode, buffer)."""
    signature = inspect.signature(policy.save_model)
    params = list(signature.parameters.values())
    has_varargs = any(param.kind == inspect.Parameter.VAR_POSITIONAL for param in params)
    if has_varargs or len(params) >= 2:
        return policy.save_model(episode, replay_buffer)
    return policy.save_model(episode)
