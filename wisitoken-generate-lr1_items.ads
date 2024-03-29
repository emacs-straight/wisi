--  Abstract :
--
--  Types and operatorion for LR(1) items.
--
--  Copyright (C) 2003, 2008, 2013 - 2015, 2017 - 2021 Free Software Foundation, Inc.
--
--  This file is part of the WisiToken package.
--
--  The WisiToken package is free software; you can redistribute it
--  and/or modify it under the terms of the GNU General Public License
--  as published by the Free Software Foundation; either version 3, or
--  (at your option) any later version. The WisiToken package is
--  distributed in the hope that it will be useful, but WITHOUT ANY
--  WARRANTY; without even the implied warranty of MERCHANTABILITY or
--  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
--  License for more details. You should have received a copy of the
--  GNU General Public License distributed with the WisiToken package;
--  see file GPL.txt. If not, write to the Free Software Foundation,
--  59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
--
--  As a special exception, if other files instantiate generics from
--  this unit, or you link this unit with other files to produce an
--  executable, this unit does not by itself cause the resulting
--  executable to be covered by the GNU General Public License. This
--  exception does not however invalidate any other reasons why the
--  executable file might be covered by the GNU Public License.

pragma License (Modified_GPL);

with Interfaces;
with SAL.Gen_Definite_Doubly_Linked_Lists_Sorted;
with SAL.Gen_Unbounded_Definite_Hash_Tables;
with SAL.Gen_Unbounded_Definite_Red_Black_Trees;
with SAL.Gen_Unbounded_Definite_Vectors.Gen_Comparable;
with WisiToken.Productions;
package WisiToken.Generate.LR1_Items is
   use all type Interfaces.Unsigned_16;

   subtype Lookahead_Index_Type is Token_ID range 0 .. 127;
   type Lookahead is array (Lookahead_Index_Type) of Boolean with Pack;
   for Lookahead'Size use 128;
   --  Picking a type for Lookahead is not straight-forward. The
   --  operations required are (called numbers are for LR1 generate
   --  ada_lite):
   --
   --  to_lookahead (token_id)
   --     Requires allocating memory dynamically:
   --        an unconstrained array range (first_terminal .. last_terminal) for (1),
   --        a smaller unconstrained array for (2), that grows as items are added
   --        individual list elements for (3).
   --
   --     lr1_items.to_lookahead        called 4_821_256 times in (2)
   --     sorted_token_id_lists.to_list called 4_821_256 times in (3)
   --
   --  for tok_id of lookaheads loop
   --     sorted_token_id_lists__iterate called 5_687 times in (3)
   --
   --  if lookaheads.contains (tok_id) then
   --     token_id_arrays__contains called 22_177_109 in (2)
   --
   --  new_item := (... , lookaheads => old_item.lookaheads)
   --  new_item := (... , lookaheads => null_lookaheads)
   --  new_item := (... , lookaheads => propagate_lookahead)
   --     token_id_arrays.adjust called 8_437_967 times in (2)
   --     sorted_token_id_lists.adjust  8_435_797 times in (3)
   --
   --  include: add tok_id to lookaheads
   --
   --      keep sorted in token_id order, so rest of algorithm is
   --      stable/faster
   --
   --      lr1_items.include called 6_818_725 times in (2)
   --
   --  lookaheads /= lookaheads
   --     if using a container, container must override "="
   --
   --  We've tried:
   --
   --  (1) Token_ID_Set (unconstrained array of boolean, allocated directly) - slower than (4)
   --
   --      Allocates more memory than (2), but everything else is fast,
   --      and it's not enough memory to matter.
   --
   --      Loop over lookaheads is awkward:
   --      for tok_id in lookaheads'range loop
   --        if lookaheads (tok_id) then
   --           ...
   --
   --  (2) Instantiation of SAL.Gen_Unbounded_Definite_Vectors (token_id_arrays) - slower than (1).
   --
   --      Productions RHS is also token_id_arrays, so gprof numbers are
   --      hard to sort out. Could be improved with a custom container, that
   --      does sort and insert internally. Insert is inherently slow.
   --
   --  (3) Instantiation of SAL.Gen_Definite_Doubly_Linked_Lists_Sorted - slower than (2)
   --
   --  (4) Fixed length constrained array of Boolean, packed to 128 bits - fastest
   --      Big enough for Ada, Java, Python. Fastest because in large
   --      grammars the time is dominated by Include, and GNAT optimizes it
   --      to use register compare of 64 bits at a time.

   Null_Lookahead : constant Lookahead := (others => False);

   type Item is record
      Prod       : Production_ID;
      Dot        : Token_ID_Arrays.Extended_Index := Token_ID_Arrays.No_Index;
      --  Token after item Dot. If after last token, value is No_Index.
      Lookaheads : Lookahead                      := (others => False);
   end record;

   function To_Lookahead (Item : in Token_ID) return Lookahead;

   function Lookahead_Image (Item : in Lookahead; Descriptor : in WisiToken.Descriptor) return String;
   --  Returns the format used in parse table output.

   function Image
     (Grammar         : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor      : in WisiToken.Descriptor;
      Item            : in LR1_Items.Item;
      Show_Lookaheads : in Boolean)
     return String;

   function Item_Compare (Left, Right : in Item) return SAL.Compare_Result;
   --  Sort Item_Lists in ascending order of Prod.Nonterm, Prod.RHS, Dot;
   --  ignores Lookaheads.
   --
   --  In an LALR kernel there can be only one Item with Prod, but that
   --  is not true in an Item_Set produced by Closure.

   package Item_Lists is new SAL.Gen_Definite_Doubly_Linked_Lists_Sorted (Item, Item_Compare);

   procedure Include
     (Item  : in out LR1_Items.Item;
      Value : in     Lookahead;
      Added :    out Boolean);
   --  Add Value to Item.Lookahead.
   --
   --  Added is True if Value was not already present.
   --
   --  Does not exclude Propagate_ID.

   procedure Include
     (Item       : in out LR1_Items.Item;
      Value      : in     Lookahead;
      Added      :    out Boolean;
      Descriptor : in     WisiToken.Descriptor);
   --  Add Value to Item.Lookahead, excluding Propagate_ID.

   procedure Include
     (Item       : in out LR1_Items.Item;
      Value      : in     Lookahead;
      Descriptor : in     WisiToken.Descriptor);
   --  Add Value to Item.Lookahead, excluding Propagate_ID.

   type Goto_Item is record
      Symbol : Token_ID := Invalid_Token_ID;
      --  If Symbol is a terminal, this is a shift and goto state action.
      --  If Symbol is a non-terminal, this is a post-reduce goto state action.
      State  : State_Index := State_Index'Last;
   end record;

   function Symbol (Item : in Goto_Item) return Token_ID is (Item.Symbol);
   function Token_ID_Compare (Left, Right : in Token_ID) return SAL.Compare_Result is
     (if Left > Right then SAL.Greater
      elsif Left < Right then SAL.Less
      else SAL.Equal);
   --  Sort Goto_Item_Lists in ascending order of Symbol.

   package Goto_Item_Arrays is new SAL.Gen_Unbounded_Definite_Vectors
     (Positive_Index_Type, Goto_Item, (Token_ID'Last, State_Index'Last));
   --  For temporary lists

   package Goto_Item_Lists is new SAL.Gen_Unbounded_Definite_Red_Black_Trees
     (Element_Type => Goto_Item,
      Key_Type     => Token_ID,
      Key          => Symbol,
      Key_Compare  => Token_ID_Compare);
   subtype Goto_Item_List is Goto_Item_Lists.Tree;
   --  Goto_Item_Lists don't get very long, so red_black_trees is only
   --  barely faster than doubly_linked_lists_sorted.

   function Get_Dot_IDs
     (Grammar    : in WisiToken.Productions.Prod_Arrays.Vector;
      Set        : in Item_Lists.List;
      Descriptor : in WisiToken.Descriptor)
     return Token_ID_Arrays.Vector;

   package Unsigned_16_Arrays is new SAL.Gen_Unbounded_Definite_Vectors
     (Positive, Interfaces.Unsigned_16, Default_Element => Interfaces.Unsigned_16'Last);
   function Compare_Unsigned_16 (Left, Right : in Interfaces.Unsigned_16) return SAL.Compare_Result is
     (if Left > Right then SAL.Greater
      elsif Left < Right then SAL.Less
      else SAL.Equal);

   package Unsigned_16_Arrays_Comparable is new Unsigned_16_Arrays.Gen_Comparable (Compare_Unsigned_16);

   subtype Item_Set_Tree_Key is Unsigned_16_Arrays_Comparable.Vector;
   --  We want a key that is fast to compare, and has enough info to
   --  significantly speed the search for an item set. So we convert all
   --  relevant data in an item into a string of integers. We need 16 bit
   --  because Ada token_ids max is 332. LR1 keys include lookaheads,
   --  LALR keys do not.

   Empty_Key : Item_Set_Tree_Key renames Unsigned_16_Arrays_Comparable.Empty_Vector;

   type Item_Set_Tree_Node is record
      Key   : Item_Set_Tree_Key   := Unsigned_16_Arrays_Comparable.Empty_Vector;
      Hash  : Positive            := 1;
      State : Unknown_State_Index := Unknown_State;
   end record;

   type Item_Set is record
      Set       : Item_Lists.List;
      Goto_List : Goto_Item_List;
      Dot_IDs   : Token_ID_Arrays.Vector;
      Tree_Node : Item_Set_Tree_Node; --  Avoids building an aggregate to insert in the tree.
   end record;

   function Filter
     (Set        : in     Item_Set;
      Grammar    : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor : in     WisiToken.Descriptor;
      Include    : access function
        (Grammar    : in WisiToken.Productions.Prod_Arrays.Vector;
         Descriptor : in WisiToken.Descriptor;
         Item       : in LR1_Items.Item)
        return Boolean)
     return Item_Set;
   --  Return a deep copy of Set, including only items for which Include returns True.

   function In_Kernel
     (Grammar    : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor : in WisiToken.Descriptor;
      Item       : in LR1_Items.Item)
     return Boolean;
   --  For use with Filter; [dragon] sec 4.7 pg 240

   function Find
     (Item : in LR1_Items.Item;
      Set  : in Item_Set)
     return Item_Lists.Cursor;
   --  Return an item from Set that matches Item.Prod, Item.Dot.
   --
   --  Return No_Element if not found.

   function Find
     (Prod : in Production_ID;
      Dot : in Token_ID_Arrays.Extended_Index;
      Set  : in Item_Set)
     return Item_Lists.Cursor;
   --  Return an item from Set that matches Prod, Dot.
   --
   --  Return No_Element if not found.

   package Item_Set_Arrays is new SAL.Gen_Unbounded_Definite_Vectors
     (State_Index, Item_Set, Default_Element => (others => <>));
   subtype Item_Set_List is Item_Set_Arrays.Vector;
   --  Item_Set_Arrays.Vector holds state item sets indexed by state, for
   --  iterating in state order. See also Item_Set_Trees.

   function Hash_Sum_32 (Key : in Item_Set_Tree_Key; Rows : in Positive) return Positive
   with Post => Hash_Sum_32'Result <= Rows;

   procedure Compute_Key_Hash
     (Item_Set           : in out LR1_Items.Item_Set;
      Rows               : in     Positive;
      Grammar            : in     WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor         : in     WisiToken.Descriptor;
      Include_Lookaheads : in     Boolean);

   function To_Item_Set_Tree_Key (Node : in Item_Set_Tree_Node) return Item_Set_Tree_Key
   is (Node.Key);

   function To_Item_Set_Tree_Hash (Node : in Item_Set_Tree_Node; Rows : in Positive) return Positive;

   package Item_Set_Trees is new SAL.Gen_Unbounded_Definite_Hash_Tables
     (Element_Type => Item_Set_Tree_Node,
      Key_Type     => Item_Set_Tree_Key,
      Key          => To_Item_Set_Tree_Key,
      Key_Compare  => Unsigned_16_Arrays_Comparable.Compare,
      Hash         => To_Item_Set_Tree_Hash);
   --  Item_Set_Trees holds state indices sorted by Item_Set_Tree_Key,
   --  for fast Find in LR1_Item_Sets and LALR_Kernels. See also
   --  Item_Set_Arrays.

   subtype Item_Set_Tree is Item_Set_Trees.Hash_Table;

   procedure Add
     (Grammar            : in     WisiToken.Productions.Prod_Arrays.Vector;
      New_Item_Set       : in out Item_Set;
      Item_Set_List      : in out LR1_Items.Item_Set_List;
      Item_Set_Tree      : in out LR1_Items.Item_Set_Tree;
      Descriptor         : in     WisiToken.Descriptor;
      Hash_Table_Rows    : in     Positive;
      Include_Lookaheads : in     Boolean)
   with Pre => New_Item_Set.Tree_Node.State = Item_Set_List.Last_Index + 1;
   --  Set New_Item_Set.Dot_IDs, add New_Item_Set to Item_Set_Vector, Item_Set_Tree

   function Is_In
     (Item      : in Goto_Item;
      Goto_List : in Goto_Item_List)
     return Boolean;
   --  Return True if a goto on Symbol to State is found in Goto_List

   function Goto_State
     (From   : in Item_Set;
      Symbol : in Token_ID)
     return Unknown_State_Index;
   --  Return state from From.Goto_List where the goto symbol is
   --  Symbol; Unknown_State if not found.

   function Closure
     (Set                     : in Item_Set;
      Has_Empty_Production    : in Token_ID_Set;
      First_Terminal_Sequence : in Token_Sequence_Arrays.Vector;
      Grammar                 : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor              : in WisiToken.Descriptor)
     return Item_Set;
   --  Return the closure of Set over Grammar. First must be the
   --  result of First above. Makes a deep copy of Goto_List.
   --  Implements 'closure' from [dragon] algorithm 4.9 pg 232, but
   --  allows merging lookaheads into one item..

   function Productions (Set : in Item_Set) return Production_ID_Arrays.Vector;

   procedure Put
     (Grammar         : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor      : in WisiToken.Descriptor;
      Item            : in LR1_Items.Item;
      Show_Lookaheads : in Boolean := True);

   procedure Put
     (Grammar         : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor      : in WisiToken.Descriptor;
      Item            : in Item_Lists.List;
      Show_Lookaheads : in Boolean := True;
      Kernel_Only     : in Boolean := False);

   procedure Put
     (Grammar         : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor      : in WisiToken.Descriptor;
      Item            : in Item_Set;
      Show_Lookaheads : in Boolean := True;
      Kernel_Only     : in Boolean := False;
      Show_Goto_List  : in Boolean := False);

   procedure Put
     (Descriptor : in WisiToken.Descriptor;
      List       : in Goto_Item_List);
   procedure Put
     (Grammar         : in WisiToken.Productions.Prod_Arrays.Vector;
      Descriptor      : in WisiToken.Descriptor;
      Item            : in Item_Set_List;
      Show_Lookaheads : in Boolean := True);
   --  Put Item to Ada.Text_IO.Standard_Output. Does not end with New_Line.

end WisiToken.Generate.LR1_Items;
