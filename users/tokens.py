from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.views import TokenObtainPairView
from datetime import timedelta
from django.contrib.auth import authenticate
from rest_framework import serializers
import uuid

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    username = serializers.CharField()

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['login_id'] = str(user.current_login_id)
        return token

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.username_field in self.fields:
            self.fields[self.username_field].required = False

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')
        target_role = getattr(self, 'target_role', None)

        if not username or not password:
            raise serializers.ValidationError('Username and password are required.')
            
        print(f"DEBUG AUTH: Attempting direct login for input: '{username}' (Target Role: {target_role})", flush=True)

        from django.contrib.auth import get_user_model
        User = get_user_model()
        role_filter = {'role': target_role} if target_role else {}
        
        user_obj = User.objects.filter(username=username, **role_filter).first()
        if not user_obj:
            user_obj = User.objects.filter(email__iexact=username, **role_filter).first()
        if not user_obj:
            user_obj = User.objects.filter(phone=username, **role_filter).first()

        if not user_obj:
            print("DEBUG AUTH: User not found.", flush=True)
            from rest_framework import exceptions
            raise exceptions.AuthenticationFailed('No active account found with the given credentials')

        print(f"DEBUG AUTH: Found user {user_obj.username} (ExtID: {user_obj.external_id})", flush=True)

        if not user_obj.check_password(password):
            print("DEBUG AUTH: Incorrect password.", flush=True)
            from rest_framework import exceptions
            raise exceptions.AuthenticationFailed('No active account found with the given credentials')

        if not user_obj.is_active:
            print("DEBUG AUTH: User is not active.", flush=True)
            from rest_framework import exceptions
            raise exceptions.AuthenticationFailed('This account is not active.')

        self.user = user_obj

        new_login_id = uuid.uuid4()
        self.user.current_login_id = new_login_id
        self.user.save(update_fields=['current_login_id'])
        print(f"DEBUG AUTH: Generated new login_id for {self.user.username}: {new_login_id}", flush=True)
        
        # Broadcast session invalidation to any old active websockets
        try:
            from channels.layers import get_channel_layer
            from asgiref.sync import async_to_sync
            channel_layer = get_channel_layer()
            if channel_layer:
                group_name = f"rider_{self.user.id}" if self.user.role == 'RIDER' else f"rodie_{self.user.id}"
                async_to_sync(channel_layer.group_send)(
                    group_name,
                    {
                        "type": "session_invalidated",
                        "message": "You have been logged out because you logged in on another device."
                    }
                )
        except Exception as e:
            print(f"DEBUG AUTH: Could not send session_invalidated to old websocket: {e}", flush=True)
        
        refresh = self.get_token(self.user)
        long_life = timedelta(days=365*50)
        refresh.set_exp(lifetime=long_life)
        access = refresh.access_token
        access.set_exp(lifetime=long_life)
        
        return {
            "refresh": str(refresh),
            "access": str(access),
            "user": {
                'id': self.user.id,
                'username': self.user.username,
                'email': self.user.email,
                'phone': self.user.phone,
                'role': self.user.role,
                'external_id': self.user.external_id,
                'services_selected': getattr(self.user, 'services_selected', False),
                'is_approved': getattr(self.user, 'is_approved', False),
            }
        }

class RiderTokenObtainPairSerializer(CustomTokenObtainPairSerializer):
    target_role = 'RIDER'
    def validate(self, attrs):
        data = super().validate(attrs)
        if self.user.role != 'RIDER':
            raise serializers.ValidationError('This account is not a Rider account.')
        return data

class RoadieTokenObtainPairSerializer(CustomTokenObtainPairSerializer):
    target_role = 'RODIE'
    def validate(self, attrs):
        data = super().validate(attrs)
        print(f"DEBUG ROADIE LOGIN: User role is {self.user.role}", flush=True)
        if self.user.role != 'RODIE':
            print(f"DEBUG ROADIE LOGIN: Role mismatch! Expected RODIE, got {self.user.role}", flush=True)
            raise serializers.ValidationError('This account is not a Roadie account.')
        return data

class WorkshopTokenObtainPairSerializer(CustomTokenObtainPairSerializer):
    target_role = 'WORKSHOP'

    def validate(self, attrs):
        data = super().validate(attrs)
        if self.user.role != 'WORKSHOP':
            raise serializers.ValidationError('This account is not a Workshop account.')
        return data

class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer

class RiderLoginView(TokenObtainPairView):
    serializer_class = RiderTokenObtainPairSerializer

class RoadieLoginView(TokenObtainPairView):
    serializer_class = RoadieTokenObtainPairSerializer

class WorkshopLoginView(TokenObtainPairView):
    serializer_class = WorkshopTokenObtainPairSerializer
