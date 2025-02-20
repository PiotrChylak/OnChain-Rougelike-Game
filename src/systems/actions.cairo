use dojo_starter::models::{Direction, Position, MazeModel};
use origami_map::map::Map;
use origami_map::generators::mazer::Mazer;
use starknet::{ContractAddress};

// define the interface
#[starknet::interface]
trait IActions<T> {
    fn spawn(ref self: T);
    fn move(ref self: T, direction: Direction);
    fn flash(ref self: T, direction: Direction);
    fn teleport(ref self: T, x_value: u32, y_value: u32);
    fn generate_maze(ref self: T, width: u8, height: u8);
}

// dojo decorator
#[dojo::contract]
pub mod actions {
    use super::{IActions, Direction, Position, NextPosition, FlashPosition, TeleportPosition, GenerateMaze, check_collision_with_wall, felt252_to_bit_array};
    use starknet::{ContractAddress, get_caller_address};
    use dojo_starter::models::{Vec2, Moves, DirectionsAvailable, MazeModel};

    use dojo::model::{ModelStorage, ModelValueStorage};
    use dojo::event::EventStorage;

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct Moved {
        #[key]
        pub player: ContractAddress,
        pub direction: Direction,
    }

    #[abi(embed_v0)]
    impl ActionsImpl of IActions<ContractState> {
        fn generate_maze(ref self: ContractState, width: u8, height: u8){
            let mut world = self.world_default();
            let id = 1;
            let maze = GenerateMaze(width, height);
            let bit_maze = felt252_to_bit_array(maze, width, height);
            
            let new_maze = MazeModel {id, width, height, bit_maze};


            world.write_model(@new_maze);
        }

        fn spawn(ref self: ContractState) {
            // Get the default world.
            let mut world = self.world_default();

            // Get the address of the current caller, possibly the player's address.
            let player = get_caller_address();
            // Retrieve the player's current position from the world.
            let position: Position = world.read_model(player);

            // Update the world state with the new data.

            // 1. Move the player's position 10 units in both the x and y direction.
            let new_position = Position {
                player, vec: Vec2 { x: position.vec.x + 10, y: position.vec.y + 10 }
            };

            // Write the new position to the world.
            world.write_model(@new_position);

            // 2. Set the player's remaining moves to 100.
            let moves = Moves {
                player, remaining: 100, last_direction: Direction::None(()), can_move: true
            };

            // Write the new moves to the world.
            world.write_model(@moves);
        }

        // Implementation of the move function for the ContractState struct.
        fn move(ref self: ContractState, direction: Direction) {
            // Get the address of the current caller, possibly the player's address.
            let mut world = self.world_default();

            let player = get_caller_address();

            // Retrieve the player's current position and moves data from the world.
            let position: Position = world.read_model(player);
            let mut moves: Moves = world.read_model(player);

            // Update the last direction the player moved in.
            moves.last_direction = direction;

            // Calculate the player's next position based on the provided direction.
            let next = NextPosition(position, direction);

            if(!check_collision_with_wall(next.vec.x, next.vec.y, world.read_model(1))){
                // Deduct one from the player's remaining moves.
                moves.remaining -= 1;
                
                // Write the new position to the world.
                world.write_model(@next);

                // Write the new moves to the world.
                world.write_model(@moves);

                // Emit an event to the world to notify about the player's move.
                world.emit_event(@Moved { player, direction });
            }
        
        //TODO information that you cant move here emitet as event, meaby do event model when informations like that will be stored.
        
        }


        fn teleport(ref self: ContractState, x_value: u32, y_value: u32){
            let mut world = self.world_default();

            let player = get_caller_address();

            let position: Position = world.read_model(player);
            let mut moves: Moves = world.read_model(player);

            moves.remaining -= 5;

            let direction = moves.last_direction;

            let new_position = TeleportPosition(position, x_value, y_value);

            world.write_model(@new_position);

            world.write_model(@moves);

            world.emit_event(@Moved { player, direction});
        }

        fn flash(ref self: ContractState, direction: Direction) {
            let mut world = self.world_default();

            let player = get_caller_address();

            let position: Position = world.read_model(player);
            let mut moves: Moves = world.read_model(player);

            moves.remaining -= 2;

            moves.last_direction = direction;

            let next = FlashPosition(position, direction);

            world.write_model(@next);

            world.write_model(@moves);

            world.emit_event(@Moved {player, direction});

        }

    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Use the default namespace "dojo_starter". This function is handy since the ByteArray
        /// can't be const.
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"dojo_starter")
        }
    }
}


// Define function like this:

fn NextPosition(mut position: Position, direction: Direction) -> Position {
    match direction {
        Direction::None => { return position; },
        Direction::Left => { position.vec.x -= 1; },
        Direction::Right => { position.vec.x += 1; },
        Direction::Up => { position.vec.y -= 1; },
        Direction::Down => { position.vec.y += 1; },
    };
    position
}

fn FlashPosition(mut position: Position, direction: Direction) -> Position{
    match direction {
        Direction::None => { return position; },
        Direction::Left => { position.vec.x -= 2; },
        Direction::Right => { position.vec.x += 2; },
        Direction::Up => { position.vec.y -= 2; },
        Direction::Down => { position.vec.y += 2; },
    };
    position
}

fn TeleportPosition(mut position: Position, x_value: u32, y_value: u32) -> Position{
    position.vec.x = x_value;
    position.vec.y = y_value;
    position
}

//TODO maze is generated with 1 less width than expected and i have to fix that

fn GenerateMaze(width: u8, height: u8) -> felt252{
    let w = width;
    let h = height;
    let order = 0;
    let seed = 'SEED';
    let maze_map = Mazer::generate(w, h, order, seed);
    maze_map
}

fn felt252_to_bit_array(value: felt252, width: u8, height: u8) -> Array<u8> { //For now maze is max 15x16 or 16x15
    let mut bits = ArrayTrait::new();
    let mut num: u256 = value.try_into().expect('Invalid value');

    let mut i = 0;
    loop {
        if i == width * height {
            break;
        }

        let bit = num % 2;
        bits.append(bit.try_into().unwrap()); 
        num = num / 2;
        i += 1;
    };
    bits
}




fn check_collision_with_wall(player_x: u32, player_y: u32, maze: MazeModel) -> bool{
    let bit_maze = maze.bit_maze;
    let mut maze_width: u32 = maze.width.try_into().expect('Invalid value');

    if(*(bit_maze[player_x + (maze_width * player_y)]) == 0){
        return true;
    } else {
        return false;
    }
}