// -----------------------------------------------------------------------------
// sys_bus_if
//
// One master port of the system bus (BUS-02 req/dir/ready protocol, D-HL-7).
// Instantiate one per master; the interconnect connects to each through the
// `slave` modport.
//
// Protocol:
//   - The master raises req with dir/addr (and wdata when dir = 1) and holds
//     them stable until the access is accepted.
//   - Write (dir = 1): accepted in the clock where wready = 1; the write takes
//     effect at the edge ending that clock, and req drops at that edge.
//   - Read  (dir = 0): accepted in the clock where rready = 1 (side effect at
//     the edge ending that clock); rdata is valid the clock after rready.
//   - wready/rready are combinational from the interconnect in the same clock
//     and must not depend combinationally on wdata.
//   - An unmapped address answers ready = 1 and rdata = 0.
// -----------------------------------------------------------------------------

interface sys_bus_if #(
  parameter ADDR_W = 16,
  parameter DATA_W = 16
);

  logic              req;
  logic              dir;     // 1 = write, 0 = read
  logic [ADDR_W-1:0] addr;
  logic [DATA_W-1:0] wdata;
  logic              wready;  // write accepted this clock
  logic              rready;  // read accepted this clock
  logic [DATA_W-1:0] rdata;   // valid the clock after rready

  // Bus master (e.g. host_link is master 0)
  modport master (
    output req,
    output dir,
    output addr,
    output wdata,
    input  wready,
    input  rready,
    input  rdata
  );

  // Interconnect side of a master port
  modport slave (
    input  req,
    input  dir,
    input  addr,
    input  wdata,
    output wready,
    output rready,
    output rdata
  );

  // Passive observer (assertions, scoreboards)
  modport monitor (
    input req,
    input dir,
    input addr,
    input wdata,
    input wready,
    input rready,
    input rdata
  );

endinterface
