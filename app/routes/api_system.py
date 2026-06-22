"""System info API routes (§4.11)."""

import os
import platform

from flask import Blueprint, jsonify

from app.settings import get_db_path, get_data_dir
from app.settings import BIN_REGISTRY
from app.process.manager import get_version
from . import auth_required

api_system = Blueprint('api_system', __name__, url_prefix='/api/system')


@api_system.route('/info', methods=['GET'])
@auth_required
def system_info():
    db_size = '0 B'
    db_path = get_db_path()
    if os.path.exists(db_path):
        size = os.path.getsize(db_path)
        from app.utils.helpers import format_size
        db_size = format_size(size)

    bins = {}
    for name in BIN_REGISTRY:
        display_name = name if name != 'sing-box' else 'sing-box'
        bins[name] = get_version(display_name)

    return jsonify({
        'platform': platform.platform(),
        'python': platform.python_version(),
        'db_size': db_size,
        'bins': bins,
    })
