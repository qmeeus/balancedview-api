import os
import uuid


class Development:
    DEBUG = True
    SECRET_KEY = os.environ.get("SECRET_KEY", uuid.uuid4().hex)


class Production(Development):

    DEBUG = False
