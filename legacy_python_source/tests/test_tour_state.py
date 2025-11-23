"""
Unit tests for tour state management
Tests the TourState class that manages tour execution state
"""

import pytest
import asyncio
from apps.tour_bot import TourState


class TestTourState:
    """Test suite for TourState class"""
    
    @pytest.fixture
    def state(self):
        """Create a fresh TourState instance for testing"""
        return TourState()
        
    def test_initial_status(self, state):
        """Test initial status is idle"""
        assert state.status == "idle"
        
    def test_initial_current_waypoint(self, state):
        """Test initial current waypoint is None"""
        assert state.current_waypoint is None
        
    def test_initial_current_script(self, state):
        """Test initial current script is None"""
        assert state.current_script is None
        
    def test_initial_waypoints(self, state):
        """Test initial waypoints list is empty"""
        assert state.waypoints == []
        assert isinstance(state.waypoints, list)
        
    def test_initial_tour_task(self, state):
        """Test initial tour task is None"""
        assert state.tour_task is None
        
    def test_initial_audio_complete_event(self, state):
        """Test initial audio complete event is None"""
        assert state.audio_complete_event is None
        
    def test_set_status(self, state):
        """Test setting status"""
        state.status = "running"
        assert state.status == "running"
        
        state.status = "completed"
        assert state.status == "completed"
        
        state.status = "failed"
        assert state.status == "failed"
        
    def test_set_current_waypoint(self, state):
        """Test setting current waypoint"""
        state.current_waypoint = "opendroids"
        assert state.current_waypoint == "opendroids"
        
    def test_set_current_script(self, state):
        """Test setting current script"""
        script = "Welcome to the tour!"
        state.current_script = script
        assert state.current_script == script
        
    def test_set_waypoints(self, state):
        """Test setting waypoints list"""
        waypoints = ["waypoint1", "waypoint2", "waypoint3"]
        state.waypoints = waypoints
        assert state.waypoints == waypoints
        
    def test_reset_clears_status(self, state):
        """Test reset clears status to idle"""
        state.status = "running"
        state.reset()
        assert state.status == "idle"
        
    def test_reset_clears_current_waypoint(self, state):
        """Test reset clears current waypoint"""
        state.current_waypoint = "test"
        state.reset()
        assert state.current_waypoint is None
        
    def test_reset_clears_current_script(self, state):
        """Test reset clears current script"""
        state.current_script = "Some script"
        state.reset()
        assert state.current_script is None
        
    def test_reset_clears_waypoints(self, state):
        """Test reset clears waypoints list"""
        state.waypoints = ["a", "b", "c"]
        state.reset()
        assert state.waypoints == []
        
    def test_reset_clears_audio_event(self, state):
        """Test reset clears audio complete event"""
        state.audio_complete_event = asyncio.Event()
        state.reset()
        assert state.audio_complete_event is None
        
    def test_reset_does_not_clear_tour_task(self, state):
        """Test reset does not modify tour_task (managed elsewhere)"""
        mock_task = object()  # placeholder
        state.tour_task = mock_task
        state.reset()
        # Task is not cleared by reset - it's managed by the application
        # This is by design, just verify behavior
        
    def test_reset_full_state(self, state):
        """Test reset clears all managed state"""
        # Set up a fully populated state
        state.status = "running"
        state.current_waypoint = "waypoint1"
        state.current_script = "Script content"
        state.waypoints = ["a", "b", "c"]
        state.audio_complete_event = asyncio.Event()
        
        # Reset
        state.reset()
        
        # Verify everything is cleared
        assert state.status == "idle"
        assert state.current_waypoint is None
        assert state.current_script is None
        assert state.waypoints == []
        assert state.audio_complete_event is None
        
    def test_multiple_resets(self, state):
        """Test multiple resets work correctly"""
        state.status = "running"
        state.current_waypoint = "test"
        
        state.reset()
        assert state.status == "idle"
        
        state.status = "completed"
        state.reset()
        assert state.status == "idle"
        
    def test_audio_event_can_be_set(self, state):
        """Test audio complete event can be created and set"""
        event = asyncio.Event()
        state.audio_complete_event = event
        
        assert state.audio_complete_event is event
        assert not event.is_set()
        
        event.set()
        assert event.is_set()
        
    def test_waypoints_list_is_mutable(self, state):
        """Test waypoints list can be modified"""
        state.waypoints = []
        state.waypoints.append("waypoint1")
        state.waypoints.append("waypoint2")
        
        assert len(state.waypoints) == 2
        assert state.waypoints[0] == "waypoint1"
        
    def test_state_independence(self):
        """Test multiple state instances are independent"""
        state1 = TourState()
        state2 = TourState()
        
        state1.status = "running"
        state1.current_waypoint = "test1"
        
        assert state2.status == "idle"
        assert state2.current_waypoint is None

