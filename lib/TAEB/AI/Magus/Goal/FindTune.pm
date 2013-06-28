package TAEB::AI::Magus::Goal::FindTune;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'Instrument', 'EnterCastle' }

1;

